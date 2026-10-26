import Foundation
import CoreGraphics
import AozoraKit

/// Owns the engine off the main thread. One conversion at a time, like the Java app.
actor ConversionWorker {
	private var engine: AozoraEpub?
	private var webEngine: AozoraEpub?
	private var settings: ConversionSettings?
	private var downloader: WebNovelDownloader?
	private var log = Log()

	struct Scanned: @unchecked Sendable {
		let book: PreparedBook
		let cover: CGImage?
	}

	private func engines(_ settings: ConversionSettings, log: Log) -> (AozoraEpub, AozoraEpub) {
		if let engine, let webEngine, self.settings == settings, self.log === log { return (engine, webEngine) }
		let replace = AppPaths.replaceFile
		let e = AozoraEpub(settings: settings, log: log, replaceFile: replace)
		let w = AozoraEpub(settings: AozoraEpub.webSettings(settings), log: log, replaceFile: replace)
		engine = e
		webEngine = w
		self.settings = settings
		self.log = log
		return (e, w)
	}

	/// Downloads a web novel (or an archive link) and returns the local file.
	func fetch(_ url: String, settings: ConversionSettings, cache: URL, downloads: URL, log: Log) async throws -> URL? {
		try await AozoraEpub.fetch(url, settings: settings, cacheDirectory: cache, downloadDirectory: downloads, log: log) { [weak self] d in
			Task { await self?.setDownloader(d) }
		}
	}

	private func setDownloader(_ d: WebNovelDownloader) { downloader = d }

	/// Scans a file; archives with several texts yield several books.
	func scan(_ file: URL, isWeb: Bool, settings: ConversionSettings, log: Log) throws -> [Scanned] {
		let (e, w) = engines(settings, log: log)
		let engine = isWeb ? w : e
		return try engine.prepare(file).map { Scanned(book: $0, cover: $0.coverPreview()) }
	}

	func convert(_ book: PreparedBook, isWeb: Bool, settings: ConversionSettings, log: Log, dst: URL?, progress: @escaping @Sendable (Double) -> Void) throws -> URL {
		let (e, w) = engines(settings, log: log)
		let engine = isWeb ? w : e
		return try engine.convert(book, dstDirectory: dst, progress: progress)
	}

	func outputURL(_ book: PreparedBook, isWeb: Bool, settings: ConversionSettings, log: Log, dst: URL?) -> URL {
		let (e, w) = engines(settings, log: log)
		return (isWeb ? w : e).outputURL(for: book, in: dst)
	}

	func illustration(_ book: PreparedBook, index: Int) -> CGImage? {
		book.imageInfoReader.image(index)
	}

	nonisolated func cancel() {
		Task { await self._cancel() }
	}

	private func _cancel() {
		engine?.cancel()
		webEngine?.cancel()
		downloader?.cancel()
	}
}

/// Where the app keeps its files.
enum AppPaths {
	static var support: URL {
		let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Aozora Ebooks", isDirectory: true)
		try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}
	static var profiles: URL {
		let url = support.appendingPathComponent("Profiles", isDirectory: true)
		try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
		return url
	}
	/// Optional character substitutions (the Java app's replace.txt).
	static var replaceFile: URL? {
		let url = support.appendingPathComponent("replace.txt")
		return FileManager.default.fileExists(atPath: url.path) ? url : nil
	}
}
