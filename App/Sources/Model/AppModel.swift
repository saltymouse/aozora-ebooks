import SwiftUI
import AozoraKit
import UniformTypeIdentifiers

/// App state: settings, the shelf of jobs, and the conversion queue.
@MainActor @Observable
final class AppModel {
	var settings: ConversionSettings { didSet { saveSettings() } }
	/// Name of the device preset last applied (nil once settings are hand-tuned).
	var presetName: String? { didSet { UserDefaults.standard.set(presetName, forKey: "presetName") } }
	let presets = DevicePreset.loadAll()
	var profiles: [Profile] = []

	var jobs: [BookJob] = []
	/// The job waiting in the review sheet.
	var reviewing: BookJob?
	var showLog = false
	var alert: String?

	private let worker = ConversionWorker()
	private var running = false
	private var reviewContinuation: CheckedContinuation<ReviewDecision, Never>?
	private var kindlegenContinuation: CheckedContinuation<Bool, Never>? {
		didSet { askKindlegen = kindlegenContinuation != nil }
	}
	/// Shows the "this preset needs kindlegen" prompt.
	var askKindlegen = false

	func answerKindlegen(useEpub: Bool) {
		kindlegenContinuation?.resume(returning: useEpub)
		kindlegenContinuation = nil
	}

	/// Keeps the preset's layout but writes EPUB (Kindle accepts EPUB via Send to Kindle).
	func makeEpubInstead() {
		settings.ext = ".epub"
		if let preset = currentPreset, preset.ini["Ext"]?.hasPrefix(".mobi") == true { presetName = nil }
	}
	/// Title/cover choices remembered per file this session (Java "表紙履歴").
	private var history: [String: ReviewHistory] = [:]

	enum ReviewDecision { case convert, skip, cancelAll }

	struct ReviewHistory {
		var title, creator: String
		var titleAs, creatorAs, publisher: String?
		var cover: PreparedBook.Cover?
	}

	init() {
		if let data = UserDefaults.standard.data(forKey: "settings"), let s = try? JSONDecoder().decode(ConversionSettings.self, from: data) {
			settings = s
		} else {
			var s = ConversionSettings()
			if let books = DevicePreset.loadAll().first(where: { $0.file == "apple_books.ini" }) { s.apply(ini: books.ini) }
			settings = s
		}
		presetName = UserDefaults.standard.string(forKey: "presetName") ?? "Apple Books (iPhone / iPad / Mac)"
		loadProfiles()
	}

	private func saveSettings() {
		if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "settings") }
	}

	// MARK: Presets & profiles

	func apply(_ preset: DevicePreset) {
		var s = settings
		s.apply(ini: preset.ini)
		settings = s
		presetName = preset.name
	}

	var currentPreset: DevicePreset? { presets.first { $0.name == presetName } }

	struct Profile: Identifiable, Hashable {
		var id: URL { url }
		let url: URL
		let name: String
		let ini: [String: String]
	}

	func loadProfiles() {
		let files = (try? FileManager.default.contentsOfDirectory(at: AppPaths.profiles, includingPropertiesForKeys: nil)) ?? []
		profiles = files.filter { $0.pathExtension == "ini" }.compactMap { url in
			guard let data = try? Data(contentsOf: url) else { return nil }
			let p = JavaProperties.parse(data)
			return Profile(url: url, name: p["ProfileName"] ?? url.deletingPathExtension().lastPathComponent, ini: p)
		}.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
	}

	/// Saves the current settings as a Java-compatible profile .ini.
	func saveProfile(named name: String) {
		var ini = settings.ini
		ini["ProfileName"] = name
		let safe = name.replacingOccurrences(of: "/", with: "-")
		let url = AppPaths.profiles.appendingPathComponent(safe + ".ini")
		try? JavaProperties.serialize(ini, comment: "AozoraEpub3 Profile").write(to: url, atomically: true, encoding: .isoLatin1)
		loadProfiles()
	}

	func apply(_ profile: Profile) {
		var s = settings
		s.apply(ini: profile.ini)
		settings = s
		presetName = nil
	}

	func delete(_ profile: Profile) {
		try? FileManager.default.removeItem(at: profile.url)
		loadProfiles()
	}

	/// Imports an AozoraEpub3.ini, profile or preset.
	func importIni(_ url: URL) {
		guard let data = try? Data(contentsOf: url) else { return }
		var s = settings
		s.apply(ini: JavaProperties.parse(data))
		settings = s
		presetName = nil
	}

	func exportIni(to url: URL) {
		try? JavaProperties.serialize(settings.ini, comment: "AozoraEpub3 Parameters").write(to: url, atomically: true, encoding: .isoLatin1)
	}

	// MARK: Adding work

	/// Files, folders (recursively), .url shortcuts and web links.
	func add(urls: [URL]) {
		for url in urls {
			if url.isFileURL {
				var isDir: ObjCBool = false
				FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
				if isDir.boolValue {
					let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
					add(urls: items.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
				} else if url.pathExtension.lowercased() == "url", let link = Self.readInternetShortcut(url) {
					enqueue(BookJob(source: .web(link)))
				} else if AozoraEpub.supportedExtensions.contains(url.pathExtension.lowercased()) {
					enqueue(BookJob(source: .file(url)))
				}
			} else if url.scheme == "http" || url.scheme == "https" {
				enqueue(BookJob(source: .web(url.absoluteString)))
			}
		}
	}

	/// Links in pasted or dropped text.
	func add(text: String) {
		let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
		let links = detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url) ?? []
		if links.isEmpty {
			alert = String(localized: "That doesn't look like a link to a web novel or an Aozora Bunko file.")
		}
		add(urls: links)
	}

	/// The URL= line of a Windows .url shortcut.
	static func readInternetShortcut(_ url: URL) -> String? {
		guard let text = try? String(contentsOf: url, encoding: .utf8) ?? String(contentsOf: url, encoding: .isoLatin1) else { return nil }
		for line in text.components(separatedBy: .newlines) where line.hasPrefix("URL=") {
			return String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
		}
		return nil
	}

	private func enqueue(_ job: BookJob) {
		withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { jobs.append(job) }
		runQueue()
	}

	func remove(_ job: BookJob) {
		withAnimation { jobs.removeAll { $0.id == job.id } }
	}

	func clearFinished() {
		withAnimation { jobs.removeAll { $0.phase.isFinished } }
	}

	func retry(_ job: BookJob) {
		job.phase = .queued
		job.log.removeAll()
		runQueue()
	}

	func cancelAll() {
		worker.cancel()
		for job in jobs where !job.phase.isFinished { job.skip(String(localized: "Stopped.")) }
		finishReview(.cancelAll)
	}

	var isBusy: Bool { jobs.contains { $0.phase.isActive || $0.phase == .review } }

	// MARK: Queue

	private func runQueue() {
		guard !running else { return }
		running = true
		Task {
			while let job = jobs.first(where: { $0.phase == .queued }) {
				if settings.ext.hasPrefix(".mobi") && KindleGen.locate() == nil {
					// ask before doing any work that can only fail
					let useEpub = await withCheckedContinuation { kindlegenContinuation = $0 }
					kindlegenContinuation = nil
					if useEpub {
						makeEpubInstead()
					} else {
						for j in jobs where j.phase == .queued { j.skip(String(localized: "Not converted: .mobi needs kindlegen, which isn't installed.")) }
						break
					}
				}
				await process(job)
			}
			running = false
		}
	}

	private var destination: URL? {
		settings.samePath || settings.dstPath.isEmpty ? nil : URL(fileURLWithPath: settings.dstPath)
	}

	private var webCache: URL {
		settings.cachePath.isEmpty ? AozoraEpub.defaultWebCache : URL(fileURLWithPath: (settings.cachePath as NSString).expandingTildeInPath)
	}

	private func makeLog(for job: BookJob) -> Log {
		Log { entry in
			Task { @MainActor in job.log.append(entry) }
		}
	}

	private func process(_ job: BookJob) async {
		let settings = self.settings
		let log = makeLog(for: job)
		do {
			let isWeb: Bool
			if let pre = pendingScans.removeValue(forKey: job.id) {
				// a further text of an archive scanned together with the first
				isWeb = job.localFile?.pathExtension == "txt"
				attach(pre, to: job)
			} else {
				var file: URL
				switch job.source {
				case .file(let url):
					file = url
				case .web(let link):
					if let local = job.localFile {
						file = local
					} else {
						job.phase = .downloading
						let downloads = destination ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
						guard let local = try await worker.fetch(link, settings: settings, cache: webCache, downloads: downloads, log: log) else {
							job.skip(String(localized: "Nothing new to download since last time (see Settings ▸ Web ▸ Updates)."))
							return
						}
						file = local
						job.localFile = local
					}
				}
				isWeb = file.pathExtension == "txt" && job.localFile != nil
				job.phase = .reading
				let scanned = try await worker.scan(file, isWeb: isWeb, settings: settings, log: log)
				guard let first = scanned.first else {
					job.fail(String(localized: "Nothing to convert in this file.") + (job.warnings.last.map { " " + $0.text } ?? ""))
					return
				}
				attach(first, to: job)
				var insertAt = (jobs.firstIndex { $0.id == job.id } ?? jobs.count - 1) + 1
				for extra in scanned.dropFirst() {
					let sibling = BookJob(source: job.source)
					sibling.localFile = job.localFile
					attach(extra, to: sibling)
					pendingScans[sibling.id] = extra
					jobs.insert(sibling, at: insertAt)
					insertAt += 1
				}
			}
			guard let book = job.book else { return }
			applyHistory(book, job: job)

			if settings.confirm {
				job.phase = .review
				reviewing = job
				let decision = await withCheckedContinuation { reviewContinuation = $0 }
				reviewing = nil
				switch decision {
				case .convert:
					remember(book)
				case .skip:
					remember(book)
					job.skip(String(localized: "You skipped this book."))
					return
				case .cancelAll:
					job.skip(String(localized: "Stopped."))
					return
				}
			}

			job.phase = .converting(0)
			let dst = isWeb ? (destination ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) : destination
			let out = try await worker.convert(book, isWeb: isWeb, settings: self.settings, log: log, dst: dst) { p in
				Task { @MainActor in
					if case .converting = job.phase { job.phase = .converting(p) }
				}
			}
			withAnimation(.spring) { job.phase = .done(out) }
		} catch ConversionError.canceled {
			job.skip(String(localized: "Stopped."))
		} catch {
			job.fail(error.localizedDescription)
		}
	}

	private var pendingScans: [UUID: ConversionWorker.Scanned] = [:]

	private func attach(_ scanned: ConversionWorker.Scanned, to job: BookJob) {
		job.book = scanned.book
		job.title = scanned.book.title.isEmpty ? job.title : scanned.book.title
		job.author = scanned.book.creator
		job.cover = scanned.cover
	}

	// MARK: Review

	func finishReview(_ decision: ReviewDecision) {
		reviewContinuation?.resume(returning: decision)
		reviewContinuation = nil
	}

	private func historyKey(_ book: PreparedBook) -> String {
		book.srcFile.path + (book.bookInfo.textEntryName.map { "/" + $0 } ?? "")
	}

	private func remember(_ book: PreparedBook) {
		history[historyKey(book)] = ReviewHistory(title: book.title, creator: book.creator, titleAs: book.titleAs, creatorAs: book.creatorAs,
		                                          publisher: book.publisher, cover: chosenCover[ObjectIdentifier(book)])
	}

	/// Cover picked in the review sheet (kept for the history).
	var chosenCover: [ObjectIdentifier: PreparedBook.Cover] = [:]

	private func applyHistory(_ book: PreparedBook, job: BookJob) {
		guard let h = history[historyKey(book)] else { return }
		if book.title.isEmpty { book.title = h.title }
		book.titleAs = h.titleAs
		if book.creator.isEmpty { book.creator = h.creator }
		book.creatorAs = h.creatorAs
		if book.publisher == nil { book.publisher = h.publisher }
		if settings.coverHistory, let cover = h.cover {
			book.setCover(cover)
			job.cover = book.coverPreview()
		}
	}

	/// Output path shown in the review sheet.
	func plannedOutput(for job: BookJob) async -> URL? {
		guard let book = job.book else { return nil }
		let isWeb = job.localFile?.pathExtension == "txt"
		return await worker.outputURL(book, isWeb: isWeb, settings: settings, log: Log(), dst: destination)
	}

	func illustration(_ job: BookJob, index: Int) async -> CGImage? {
		guard let book = job.book else { return nil }
		return await worker.illustration(book, index: index)
	}
}
