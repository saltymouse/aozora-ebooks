import Foundation
import SwiftSoup

/// Options for downloading a web novel (the Java "Web" tab).
public struct WebOptions: Sendable {
	/// Seconds between requests (minimum 0.5).
	public var interval: Double = 0.5
	/// Treat cached chapters fetched within this many hours as updated.
	public var modifiedExpire: Double = 24
	/// Skip output when nothing was added or changed.
	public var convertUpdated = false
	/// Only output added/changed chapters.
	public var convertModifiedOnly = false
	/// With convertModifiedOnly: only the run of updates at the end.
	public var convertModifiedTail = false
	/// Only the latest N chapters (0 = all), added to the updated ones.
	public var beforeChapter = 0
	public var userAgent = ""
	/// Syosetu: follow mitemin image pages to the large image.
	public var largeImages = false

	public init() {}

	public init(_ s: ConversionSettings) {
		interval = Double(s.webInterval)
		modifiedExpire = Double(s.webModifiedExpire)
		convertUpdated = s.webConvertUpdated
		convertModifiedOnly = s.webModifiedOnly
		convertModifiedTail = s.webModifiedTail
		beforeChapter = s.webBeforeChapter ? s.webBeforeChapterCount : 0
		userAgent = s.userAgent
	}
}

/// What a web download produced.
public struct WebDownloadResult: Sendable {
	/// Aozora-format UTF-8 text (converted.txt in the cache).
	public let textFile: URL
	/// Cover saved as converted.png, if the site has one.
	public let coverFile: URL?
	public let title: String?
	public let updated: Bool
}

/// Downloads a web novel through a site definition (web/<host>/extract.txt) and writes
/// Aozora-annotated text (port of `WebAozoraConverter`, from the maintained kyukyunyorituryo
/// fork, which follows current Syosetu/Kakuyomu markup and TOC pagination).
public final class WebNovelDownloader: @unchecked Sendable {
	enum ExtractId: String {
		case COOKIE, PAGE_REGEX, PAGER_MAX, INDEX, NEXT_PAGE, LAST_PAGE, USER_AGENT
		case SERIES, TITLE, AUTHOR, DESCRIPTION, COVER_IMG, COVER_HREF
		case PAGE_NUM, PAGE_URL
		case CHILD_NODE, HREF, HREF_REGEX, UPDATE, SUB_UPDATE, CONTENT_UPDATE_LIST, SUBTITLE_LIST
		case CONTENT_CHAPTER, CONTENT_SUBTITLE, CONTENT_IMG, CONTENT_UPDATE
		case CONTENT_ARTICLE, CONTENT_PREAMBLE, CONTENT_APPENDIX
		case CONTENT_ARTICLE_SEPARATOR
		case CONTENT_ARTICLE_START, CONTENT_ARTICLE_END
		case CONTENT_PREAMBLE_START, CONTENT_PREAMBLE_END
		case CONTENT_APPENDIX_START, CONTENT_APPENDIX_END
	}

	/// One CSS query from extract.txt: "query:idx:idx" plus optional regex/replacement.
	struct ExtractInfo {
		let query: String
		let idx: [Int]?
		let pattern: JPattern?
		let replacement: String?

		init(_ queryString: String, _ pattern: JPattern?, _ replacement: String?) {
			let values = queryString.split(regex: ":")
			query = values.first ?? ""
			idx = values.count > 1 ? values.dropFirst().compactMap { Int($0) } : nil
			self.pattern = pattern
			self.replacement = replacement?.replaceAll("\\\\n", "\n")
		}

		var hasPattern: Bool { pattern != nil }
		func replace(_ s: String) -> String {
			guard let pattern, let replacement else { return s }
			return pattern.matcher(s).replaceAll(replacement)
		}
		func matches(_ s: String) -> Bool { pattern?.matcher(s).matches() ?? false }
	}

	let fqdn: String
	private var queryMap: [ExtractId: [ExtractInfo]] = [:]
	let log: Log
	private let session: URLSession

	private var options = WebOptions()
	private var canceled = false
	public private(set) var updated = false
	private var dstPath = ""
	private var urlString = ""
	private var baseUri = ""
	private var pageBaseUri = ""
	private var text = ""

	/// Hosts with a site definition.
	public static func supportedHosts(_ webDirectory: URL = AozoraResources.webDirectory) -> [String] {
		let dirs = (try? FileManager.default.contentsOfDirectory(at: webDirectory, includingPropertiesForKeys: nil)) ?? []
		return dirs.filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("extract.txt").path) }.map(\.lastPathComponent).sorted()
	}

	/// Returns nil if there is no definition for the URL's host.
	public init?(url: String, webDirectory: URL = AozoraResources.webDirectory, log: Log) {
		let trimmed = url.trimmingCharacters(in: .whitespaces)
		guard let r = trimmed.range(of: "//") else { return nil }
		let afterScheme = trimmed[r.upperBound...]
		fqdn = String(afterScheme.prefix { $0 != "/" })
		self.log = log
		let file = webDirectory.appendingPathComponent(fqdn).appendingPathComponent("extract.txt")
		guard let lines = try? TextIO.readLines(file) else {
			log.error("サイトの定義がありません: web/" + fqdn)
			return nil
		}
		for line in lines where !line.isEmpty && !line.hasPrefix("#") {
			let values = line.split(regex: "\t", limit: -1)
			guard values.count > 1, let id = ExtractId(rawValue: values[0]) else { continue }
			let pattern = values.count > 2 && !values[2].isEmpty ? JPattern.tryCompile(values[2]) : nil
			let replacement = values.count > 3 ? values[3] : nil
			queryMap[id] = values[1].split(regex: ",").map { ExtractInfo($0, pattern, replacement) }
		}
		let config = URLSessionConfiguration.default
		config.timeoutIntervalForRequest = 10
		session = URLSession(configuration: config)
	}

	public func cancel() { canceled = true }

	// MARK: - Download

	/// Downloads the work at `url` into `cacheDirectory` and writes converted.txt.
	/// Returns nil when skipped (no updates) or canceled.
	public func download(_ urlIn: String, cacheDirectory: URL, options: WebOptions) async throws -> WebDownloadResult? {
		canceled = false
		updated = true
		var opts = options
		opts.interval = max(0.5, options.interval)
		opts.modifiedExpire = max(0, options.modifiedExpire)
		self.options = opts
		text = ""

		var urlString = urlIn.trimmingCharacters(in: .whitespaces)
		if !urlString.hasSuffix("/") && !urlString.hasSuffix(".html") && !urlString.hasSuffix(".htm") && !urlString.contains("?") {
			if let url = URL(string: urlString + "/"), let (_, response) = try? await session.data(for: request(url)),
			   (response as? HTTPURLResponse)?.statusCode == 200 {
				urlString += "/"
				log.println("URL修正 : " + urlString)
			}
		}
		self.urlString = urlString
		baseUri = urlString.jsub(0, urlString.indexOf("/", urlString.indexOf("//") + 2))
		let listBaseUrl = urlString.jsub(0, urlString.lastIndexOf("/") + 1)
		pageBaseUri = listBaseUrl
		var urlFilePath = CharUtils.escapeUrlToFile(urlString.jsub(urlString.indexOf("//") + 2))
		var urlParentPath = urlFilePath
		if urlFilePath.contains("kakuyomu") || urlFilePath.contains("novelup") {
			urlFilePath += "/"
		}
		var isPath = false
		if urlFilePath.hasSuffix("/") { isPath = true; urlFilePath += "index.html" }
		else { urlParentPath = urlFilePath.jsub(0, urlFilePath.lastIndexOf("/") + 1) }

		let cachePath = cacheDirectory.path
		dstPath = cachePath + "/" + (isPath ? urlParentPath : urlFilePath + "_converted/")
		let txtFile = URL(fileURLWithPath: dstPath + "converted.txt")
		let coverImageFile = URL(fileURLWithPath: dstPath + "converted.png")
		let updateInfoFile = URL(fileURLWithPath: dstPath + "update.txt")
		try FileManager.default.createDirectory(at: txtFile.deletingLastPathComponent(), withIntermediateDirectories: true)

		let cacheFile = URL(fileURLWithPath: cachePath + "/" + urlFilePath)
		do {
			try await self.cacheFile(urlString, cacheFile, referer: nil)
			log.println(urlString + " : List Loaded.")
		} catch {
			log.warn("一覧ページの取得に失敗しました。 \(error.localizedDescription)")
			if !FileManager.default.fileExists(atPath: cacheFile.path) { return nil }
			log.println("キャッシュファイルを利用します。")
		}

		var doc = try parseHTML(cacheFile, baseUri: urlString)

		// TOC pagination (Syosetu splits long TOCs into ?p=N pages)
		let tocIndex = elements(doc, .INDEX)
		if let lastPage = elements(doc, .LAST_PAGE) {
			let href = try lastPage.attr("href")
			let query = href.split(separator: "?", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
			let lastNum = Int(query.replaceAll("[^0-9]", "")) ?? 1
			var pagerBaseUrl = href.split(separator: "=", maxSplits: 1).first.map(String.init) ?? href
			if !pagerBaseUrl.hasPrefix("http") { pagerBaseUrl = baseUri + pagerBaseUrl }
			let pagerUrls = lastNum >= 2 ? (2...lastNum).map { "\(pagerBaseUrl)=\($0)" } : []
			let pagerMax = Int(queryMap[.PAGER_MAX]?.first?.query ?? "") ?? pagerUrls.count
			log.println("ページャー最大値は\(pagerMax)")
			for pagerUrl in pagerUrls.prefix(min(pagerUrls.count, pagerMax)) {
				if canceled { return nil }
				let pagerFile = URL(fileURLWithPath: cachePath + "/" + CharUtils.escapeUrlToFile(pagerUrl.jsub(pagerUrl.indexOf("//") + 2)))
				do {
					try await sleepInterval()
					try await self.cacheFile(pagerUrl, pagerFile, referer: nil)
					log.println(pagerUrl + " : List Loaded.")
				} catch {
					log.println("一覧ページの取得に失敗しました。 ")
					if !FileManager.default.fileExists(atPath: pagerFile.path) { return nil }
					log.println("キャッシュファイルを利用します。")
				}
				let pageDoc = try parseHTML(pagerFile, baseUri: pagerUrl)
				if let index = elements(pageDoc, .INDEX)?.first(), let target = tocIndex?.first() {
					for child in index.children().array() { try target.appendChild(child.copy() as! Element) }
				}
			}
		} else {
			log.println("ページャーがありません")
		}

		if urlFilePath.contains("kakuyomu") {
			doc = try kakuyomuDocument(doc, urlString: urlString)
		}

		if let images = elements(doc, .COVER_IMG), let img = images.first() {
			try await printImage(img, outFile: coverImageFile, emit: false)
		}

		var hasTitle = false
		if let series = extractText(doc, .SERIES) { printText(series); text += "\n"; hasTitle = true }
		let title = extractText(doc, .TITLE)
		if let title { printText(title); text += "\n"; hasTitle = true }
		guard hasTitle else {
			log.error("SERIES/TITLE : タイトルがありません")
			return nil
		}
		if let author = extractText(doc, .AUTHOR) { printText(author) }
		text += "\n"
		if let description = firstElement(doc, .DESCRIPTION) {
			text += "\n［＃区切り線］\n\n［＃ここから２字下げ］\n［＃ここから２字上げ］\n"
			try await printNode(description, start: nil, end: nil, noHr: true)
			text += "\n［＃ここで字上げ終わり］\n［＃ここで字下げ終わり］\n\n［＃区切り線］\n\n"
		}
		let contentsUpdate = extractText(doc, .UPDATE)

		var preChapterTitle = ""
		var chapterHrefs: [String] = []
		let hrefs = elements(doc, .HREF)
		if hrefs == nil && queryMap[.HREF] != nil { log.warn("HREF : 各話のリンク先URLが取得できません") }
		let subtitles = extractStrings(doc, .SUBTITLE_LIST)
		if subtitles == nil && queryMap[.SUBTITLE_LIST] != nil { log.warn("SUBTITLE_LIST : 各話タイトルが取得できません") }

		var noUpdateUrls: Set<String>? = nil
		var postDateList: [String]? = nil
		if hrefs == nil {
			let pageNumString = extractText(doc, .PAGE_NUM)
			if pageNumString == nil && queryMap[.PAGE_NUM] != nil { log.warn("PAGE_NUM : ページ数が取得できません") }
			let pageNum = Int(pageNumString ?? "") ?? -1
			let pageUrlElement = firstElement(doc, .PAGE_URL)
			if pageUrlElement == nil && queryMap[.PAGE_URL] != nil { log.warn("PAGE_URL : ページ番号用のURLが取得できません") }
			if pageNum > 0, let pageUrlElement, let info = queryMap[.PAGE_URL]?.first {
				for i in 1...pageNum {
					var pageUrl = info.replace(((try? pageUrlElement.attr("href")) ?? "") + "\t\(i)")
					if !pageUrl.hasPrefix("http") { pageUrl = (pageUrl.hasPrefix("/") ? baseUri : listBaseUrl) + pageUrl }
					chapterHrefs.append(pageUrl)
				}
			} else if elements(doc, .CONTENT_ARTICLE) != nil {
				try await docToAozoraText(doc, newChapter: false, listSubTitle: nil, postDate: nil)
			} else {
				log.error("一覧のURLが取得できませんでした")
				return nil
			}
		} else if let hrefs {
			let updates = elements(doc, .SUB_UPDATE)
			if updates == nil && queryMap[.SUB_UPDATE] != nil { log.warn("SUB_UPDATE : 更新確認情報が取得できません") }
			if let updates { noUpdateUrls = createNoUpdateUrls(updateInfoFile, urlString, listBaseUrl, contentsUpdate, hrefs, updates) }
			let hrefInfo = queryMap[.HREF]!.first!
			for href in hrefs.array() {
				let hrefString = (try? href.attr("href")) ?? ""
				guard !hrefString.isEmpty else { continue }
				if !hrefInfo.hasPattern || hrefInfo.matches(hrefString) {
					if let resolved = resolve(hrefString, baseUri: baseUri, listBaseUrl: listBaseUrl) { chapterHrefs.append(resolved) }
				}
			}
			postDateList = postDates(doc, .CONTENT_UPDATE_LIST)
			if postDateList == nil && queryMap[.CONTENT_UPDATE_LIST] != nil { log.warn("CONTENT_UPDATE_LIST : 一覧ページの更新日時情報が取得できません") }
		}

		if !chapterHrefs.isEmpty {
			updated = false
			let expire = Date().addingTimeInterval(-opts.modifiedExpire * 3600)
			var modifiedChapterIdx: Set<Int>? = opts.convertModifiedOnly ? [] : nil
			var lastNoModifiedChapterIdx = -1

			for (chapterIdx, chapterHref) in chapterHrefs.enumerated() {
				if canceled { return nil }
				guard !chapterHref.isEmpty else { continue }
				let chapterFile = chapterCacheFile(chapterHref, cachePath)
				var loaded = false
				let reload = noUpdateUrls != nil && !noUpdateUrls!.contains(chapterHref)
				if reload || !FileManager.default.fileExists(atPath: chapterFile.path) {
					do {
						try await sleepInterval()
						try await self.cacheFile(chapterHref, chapterFile, referer: urlString)
						log.println("[\(chapterIdx + 1)/\(chapterHrefs.count)] \(chapterHref) : Loaded.")
						updated = true
						loaded = true
					} catch {
						log.warn("htmlファイルが取得できませんでした : " + chapterHref)
					}
				}
				let modified = (try? chapterFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
				if !loaded && opts.modifiedExpire > 0 && (opts.convertModifiedOnly || opts.convertUpdated) && modified >= expire {
					log.println("[\(chapterIdx + 1)/\(chapterHrefs.count)] \(chapterHref) : Modified.")
					updated = true
				}
				if opts.convertModifiedOnly {
					if modified >= expire {
						modifiedChapterIdx!.insert(chapterIdx)
					} else {
						if opts.convertModifiedTail { modifiedChapterIdx!.removeAll() }
						lastNoModifiedChapterIdx = chapterIdx
					}
				}
			}
			if !updated {
				log.warn("「\(title ?? "")」の更新はありません")
				if opts.convertUpdated { return nil }
			}
			if opts.convertModifiedOnly {
				if opts.beforeChapter > 0 {
					if modifiedChapterIdx!.isEmpty {
						var idx = chapterHrefs.count - 1
						for _ in 0..<opts.beforeChapter { modifiedChapterIdx!.insert(idx); idx -= 1 }
					} else {
						let startIdx = max(0, lastNoModifiedChapterIdx - opts.beforeChapter + 1)
						if startIdx <= lastNoModifiedChapterIdx { for i in startIdx...lastNoModifiedChapterIdx { modifiedChapterIdx!.insert(i) } }
					}
				}
				if modifiedChapterIdx!.isEmpty {
					log.warn("追加更新分はありません")
					updated = false
					return nil
				}
			} else if opts.beforeChapter > 0 {
				var idx = chapterHrefs.count - 1
				modifiedChapterIdx = []
				for _ in 0..<opts.beforeChapter { modifiedChapterIdx!.insert(idx); idx -= 1 }
			}

			for (chapterIdx, chapterHref) in chapterHrefs.enumerated() {
				if canceled { return nil }
				guard modifiedChapterIdx == nil || modifiedChapterIdx!.contains(chapterIdx) else { continue }
				let chapterFile = chapterCacheFile(chapterHref, cachePath)
				guard FileManager.default.fileExists(atPath: chapterFile.path) else { continue }
				pageBaseUri = chapterHref
				if !chapterHref.hasSuffix("/") {
					let idx = chapterHref.indexOf("/", 7)
					if idx > -1 { pageBaseUri = chapterHref.jsub(0, idx) }
				}
				let chapterDoc = try parseHTML(chapterFile, baseUri: chapterHref)
				let chapterTitle = extractText(chapterDoc, .CONTENT_CHAPTER)
				var newChapter = false
				if let chapterTitle, chapterTitle != preChapterTitle {
					newChapter = true
					preChapterTitle = chapterTitle
					text += "\n［＃改ページ］\n［＃大見出し］"
					printText(preChapterTitle)
					text += "［＃大見出し終わり］\n\n"
				}
				let postDate = postDateList.flatMap { chapterIdx < $0.count ? $0[chapterIdx] : nil }
				let subTitle = subtitles.flatMap { chapterIdx < $0.count ? $0[chapterIdx] : nil }
				try await docToAozoraText(chapterDoc, newChapter: newChapter, listSubTitle: subTitle, postDate: postDate)
			}
			if let modifiedChapterIdx {
				log.println(Self.chapterRanges(modifiedChapterIdx, count: chapterHrefs.count) + "話を変換します")
			}
		}

		text += "\n［＃改ページ］\n底本： <a href=\"\(urlString)\">\(urlString)</a>\n変換日時： \(Self.dateFormat.string(from: Date()))\n"
		try text.write(to: txtFile, atomically: true, encoding: .utf8)
		canceled = false
		let hasCover = FileManager.default.fileExists(atPath: coverImageFile.path)
		return WebDownloadResult(textFile: txtFile, coverFile: hasCover ? coverImageFile : nil, title: title, updated: updated)
	}

	static let dateFormat: DateFormatter = {
		let f = DateFormatter()
		f.locale = Locale(identifier: "en_US_POSIX")
		f.dateFormat = "yyyy/MM/dd HH:mm:ss"
		return f
	}()

	/// "1-3,7" for the log.
	static func chapterRanges(_ set: Set<Int>, count: Int) -> String {
		var buf = ""
		var preIdx = -1
		var connected = false
		for idx in 0..<count where set.contains(idx) {
			if buf.isEmpty { buf = String(idx + 1) }
			else if preIdx == idx - 1 { connected = true }
			else {
				if connected { buf += "-\(preIdx + 1)" }
				connected = false
				buf += ",\(idx)"
			}
			preIdx = idx
		}
		if connected { buf += "-\(preIdx + 1)" }
		return buf
	}

	private func chapterCacheFile(_ chapterHref: String, _ cachePath: String) -> URL {
		let chapterPath = CharUtils.escapeUrlToFile(chapterHref.jsub(chapterHref.indexOf("//") + 2))
		return URL(fileURLWithPath: cachePath + "/" + chapterPath + (chapterPath.hasSuffix("/") ? "index.html" : ""))
	}

	private func resolve(_ href: String, baseUri: String, listBaseUrl: String) -> String? {
		if href.hasPrefix("http") { return URL(string: href)?.standardized.absoluteString ?? href }
		let base = href.hasPrefix("/") ? baseUri + "/" : listBaseUrl
		return URL(string: href, relativeTo: URL(string: base))?.absoluteURL.absoluteString
	}

	private func sleepInterval() async throws {
		try await Task.sleep(nanoseconds: UInt64(options.interval * 1_000_000_000))
	}

	// MARK: - Kakuyomu

	/// Kakuyomu renders its TOC from __NEXT_DATA__ JSON; rebuild a simple HTML TOC from it.
	private func kakuyomuDocument(_ doc: Document, urlString: String) throws -> Document {
		let cd = urlString.split(separator: "/").last.map(String.init) ?? ""
		guard let script = try doc.getElementById("__NEXT_DATA__"),
		      let json = try JSONSerialization.jsonObject(with: Data(script.data().utf8)) as? [String: Any],
		      let state = ((json["props"] as? [String: Any])?["pageProps"] as? [String: Any])?["__APOLLO_STATE__"] as? [String: Any],
		      let work = state["Work:" + cd] as? [String: Any] else {
			log.error("カクヨムの目次データが取得できません")
			return doc
		}
		func ref(_ o: Any?) -> String? { (o as? [String: Any])?["__ref"] as? String }
		let title = work["title"] as? String ?? ""
		let introduction = work["introduction"] as? String ?? ""
		var author = ""
		if let alt = work["alternateAuthorName"] as? String { author = alt + "／" }
		if let a = ref(work["author"]), let authorObj = state[a] as? [String: Any] { author += authorObj["activityName"] as? String ?? "" }
		var episodes: [String] = []
		for toc in work["tableOfContentsV2"] as? [Any] ?? [] {
			guard let t = ref(toc), let chapter = state[t] as? [String: Any] else { continue }
			for e in chapter["episodeUnions"] as? [Any] ?? [] { if let r = ref(e) { episodes.append(r) } }
		}
		let iso = ISO8601DateFormatter()
		iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		let isoPlain = ISO8601DateFormatter()
		let day = DateFormatter(); day.dateFormat = "yyyy年MM月dd日"
		let minute = DateFormatter(); minute.dateFormat = "yyyy/MM/dd HH:mm"
		func esc(_ s: String) -> String { CharUtils.escapeHtml(s) }
		var html = "<h1 id=\"workTitle\"><a href=\"\">\(esc(title))</a></h1>\n"
		html += "<span id=\"workAuthor-activityName\"><a href=\"\">\(esc(author))</a></span>\n"
		html += "<p id=\"introduction\">\(esc(introduction).replacingOccurrences(of: "\n", with: "<br>"))</p>\n<ol class=\"widget-toc-items\">\n"
		for e in episodes {
			guard let ep = state[e] as? [String: Any], let id = ep["id"] as? String else { continue }
			let published = (ep["publishedAt"] as? String).flatMap { iso.date(from: $0) ?? isoPlain.date(from: $0) }
			html += "<a href=\"/works/\(cd)/episodes/\(id)\">\n"
			html += "<time class=\"widget-toc-episode-datePublished\">\(published.map(day.string) ?? "")</time>\n"
			html += "<datetime class=\"episode-update\">\(published.map(minute.string) ?? "") 公開</datetime>\n</a>\n"
		}
		html += "</ol>\n"
		return try SwiftSoup.parse(html, urlString)
	}

	// MARK: - Chapter text

	private func docToAozoraText(_ doc: Document, newChapter: Bool, listSubTitle: String?, postDate postDateIn: String?) async throws {
		guard let contentDivs = elements(doc, .CONTENT_ARTICLE), contentDivs.size() > 0 else {
			log.error("CONTENT_ARTICLE : 本文が取得できません")
			return
		}
		if !newChapter { text += "\n［＃改ページ］\n" }
		if let subTitle = extractText(doc, .CONTENT_SUBTITLE) ?? listSubTitle {
			text += "［＃中見出し］"
			printText(subTitle)
			text += "［＃中見出し終わり］\n"
		}
		var postDate = postDateIn
		if let u = extractText(doc, .CONTENT_UPDATE), !u.isEmpty { postDate = u }
		if let postDate {
			text += "［＃ここから地から１字上げ］\n［＃ここから１段階小さな文字］\n"
			printText(postDate)
			text += "\n［＃ここで小さな文字終わり］\n［＃ここで字上げ終わり］\n"
		}
		text += "\n"
		if let images = elements(doc, .CONTENT_IMG), let img = images.first() { try await printImage(img, outFile: nil, emit: true) }

		if let preamble = elements(doc, .CONTENT_PREAMBLE) {
			let start = firstElement(doc, .CONTENT_PREAMBLE_START)
			let end = firstElement(doc, .CONTENT_PREAMBLE_END)
			text += "［＃区切り線］\n［＃ここから２字下げ］\n［＃ここから２字上げ］\n［＃ここから１段階小さな文字］\n\n"
			for elem in preamble.array() { try await printNode(elem, start: start, end: end, noHr: true) }
			text += "\n\n［＃ここで小さな文字終わり］\n［＃ここで字上げ終わり］\n［＃ここで字下げ終わり］\n［＃区切り線］\n\n\n"
			try preamble.remove()
		}
		let separator = queryMap[.CONTENT_ARTICLE_SEPARATOR]?.first?.query
		var first = true
		for elem in (elements(doc, .CONTENT_ARTICLE) ?? contentDivs).array() {
			if first { first = false } else {
				text += "\n"
				if let separator { text += separator }
			}
			try await printNode(elem, start: firstElement(doc, .CONTENT_ARTICLE_START), end: firstElement(doc, .CONTENT_ARTICLE_END), noHr: false)
		}
		if let appendix = elements(doc, .CONTENT_APPENDIX) {
			let start = firstElement(doc, .CONTENT_APPENDIX_START)
			let end = firstElement(doc, .CONTENT_APPENDIX_END)
			text += "\n\n［＃区切り線］\n［＃ここから２字下げ］\n［＃ここから２字上げ］\n［＃ここから１段階小さな文字］\n\n"
			for elem in appendix.array() { try await printNode(elem, start: start, end: end, noHr: true) }
			text += "\n［＃ここで小さな文字終わり］\n［＃ここで字上げ終わり］\n［＃ここで字下げ終わり］\n"
		}
	}

	private var startElement: Node?
	private var endElement: Node?
	private var noHr = false

	private func printNode(_ parent: Node, start: Node?, end: Node?, noHr: Bool) async throws {
		startElement = start
		endElement = end
		self.noHr = noHr
		_ = try await _printNode(parent)
	}

	/// Returns false when the end element was reached.
	private func _printNode(_ parent: Node) async throws -> Bool {
		for node in parent.getChildNodes() {
			if let s = startElement {
				if node === s { startElement = nil; continue }
				if node is Element { if try await !_printNode(node) { return false } }
				continue
			}
			if let e = endElement, node === e { return false }
			if let t = node as? TextNode {
				printText(t.getWholeText())
			} else if let elem = node as? Element {
				switch elem.tagName() {
				case "br":
					if elem.nextSibling() != nil { text += "\n" }
				case "div":
					if let prev = elem.previousSibling(), !isBlockNode(prev) { text += "\n" }
					if try await !_printNode(elem) { return false }
					if elem.nextSibling() != nil { text += "\n" }
				case "p":
					if try await !_printNode(elem) { return false }
					if elem.nextSibling() != nil { text += "\n" }
				case "ruby":
					printRuby(elem)
				case "img":
					try await printImage(elem, outFile: nil, emit: true)
				case "hr":
					if !noHr { text += "［＃区切り線］\n" }
				case "b":
					text += "［＃ここから太字］"; if try await !_printNode(elem) { return false }; text += "［＃ここで太字終わり］"
				case "em":
					text += "［＃丸傍点］"; if try await !_printNode(elem) { return false }; text += "［＃丸傍点終わり］"
				case "sup":
					text += "［＃上付き小文字］"; if try await !_printNode(elem) { return false }; text += "［＃上付き小文字終わり］"
				case "sub":
					text += "［＃下付き小文字］"; if try await !_printNode(elem) { return false }; text += "［＃下付き小文字終わり］"
				case "strike", "s":
					text += "［＃取消線］"; if try await !_printNode(elem) { return false }; text += "［＃取消線終わり］"
				case "tr":
					if try await !_printNode(elem) { return false }
					text += "\n"
				default:
					if try await !_printNode(elem) { return false }
				}
			}
		}
		return true
	}

	private func isBlockNode(_ node: Node) -> Bool {
		guard let elem = node as? Element else { return false }
		return ["br", "div", "p", "hr", "table"].contains(elem.tagName())
	}

	private func printRuby(_ ruby: Element) {
		for child in ruby.getChildNodes() {
			if let e = child as? Element {
				switch e.nodeName() {
				case "rt":
					text += "《"; printText((try? e.text()) ?? ""); text += "》"
				case "rb":
					text += "｜"; printText((try? e.text()) ?? "")
				default:
					break
				}
			} else if let t = child as? TextNode {
				text += "｜"
				printText(t.text())
			}
		}
	}

	/// Caches an image and writes an illustration chuki (or saves the cover).
	private func printImage(_ img: Element, outFile: URL?, emit: Bool) async throws {
		var src = (try? img.attr("src")) ?? ""
		guard !src.isEmpty else { return }
		var imagePath: String
		let idx = src.indexOf("//")
		if idx > 0 {
			imagePath = CharUtils.escapeUrlToFile(src.jsub(idx + 2))
		} else if idx == 0 && src.indexOf("mitemin") != 0 {
			// protocol-relative (Syosetu's image host)
			src = "https:" + src
			if options.largeImages {
				let imageUrl = src.replacingOccurrences(of: "userpageimage/viewimagebig/icode/", with: "")
				let pageFile = URL(fileURLWithPath: dstPath + "images/" + CharUtils.escapeUrlToFile(imageUrl) + "/index.html")
				if (try? await cacheFile(imageUrl, pageFile, referer: urlString)) != nil,
				   let page = try? parseHTML(pageFile, baseUri: imageUrl),
				   let large = try? page.getElementsByClass("imageview").first()?.children().attr("href"), !large.isEmpty {
					src = large
				}
			}
			imagePath = CharUtils.escapeUrlToFile(src)
		} else if src.hasPrefix("/") {
			imagePath = "_" + CharUtils.escapeUrlToFile(src)
			src = baseUri + src
		} else {
			imagePath = "__/" + CharUtils.escapeUrlToFile(src)
			src = pageBaseUri.hasSuffix("/") ? pageBaseUri + src : pageBaseUri + "/" + src
		}
		if imagePath.hasSuffix("/") { imagePath += "image.png" }
		let imageFile = URL(fileURLWithPath: dstPath + "images/" + imagePath)
		do {
			if let outFile {
				try? FileManager.default.removeItem(at: outFile)
				try await cacheFile(src, outFile, referer: urlString)
			} else if !FileManager.default.fileExists(atPath: imageFile.path) {
				try await cacheFile(src, imageFile, referer: urlString)
			}
		} catch {
			log.warn("画像が取得できませんでした : " + src)
		}
		if emit { text += "［＃挿絵（images/\(imagePath)）入る］\n" }
	}

	/// Appends text with Aozora special characters escaped as chuki.
	private func printText(_ s: String) {
		for ch in s.utf16 {
			switch ch {
			case "《": text += "※［＃始め二重山括弧、1-1-52］"
			case "》": text += "※［＃終わり二重山括弧、1-1-53］"
			case "［": text += "※［＃始め角括弧、1-1-46］"
			case "］": text += "※［＃終わり角括弧、1-1-47］"
			case "〔": text += "※［＃始め亀甲括弧、1-1-44］"
			case "〕": text += "※［＃終わり亀甲括弧、1-1-45］"
			case "｜": text += "※［＃縦線、1-1-35］"
			case "＃": text += "※［＃井げた、1-1-84］"
			case "※": text += "※［＃米印、1-2-8］"
			case "\t": text += " "
			case "\n", "\r": break
			default: text += String(jchars: [ch])
			}
		}
	}

	// MARK: - Extraction

	private func select(_ doc: Document, _ query: String) -> Elements? {
		guard let els = try? doc.select(query), els.size() > 0 else { return nil }
		return els
	}

	private func pick(_ els: Elements, _ idx: [Int]) -> [Element] {
		idx.compactMap { i in
			let pos = i < 0 ? els.size() + i : i
			return pos >= 0 && pos < els.size() ? els.get(pos) : nil
		}
	}

	/// Inner text of the first query that matches (several elements joined with spaces).
	func extractText(_ doc: Document, _ id: ExtractId) -> String? {
		guard let infos = queryMap[id] else { return nil }
		for info in infos {
			guard let els = select(doc, info.query) else { continue }
			var text: String? = nil
			if let idx = info.idx {
				let parts = pick(els, idx).compactMap { try? replaceHtmlText($0.html(), info) }
				if !parts.isEmpty { text = parts.joined(separator: " ") }
			}
			// Java returns nothing for queries without an index (its loop result is discarded)
			if let text, !text.isEmpty { return text }
		}
		return nil
	}

	func extractStrings(_ doc: Document, _ id: ExtractId) -> [String]? {
		guard let infos = queryMap[id] else { return nil }
		for info in infos {
			guard let els = select(doc, info.query) else { continue }
			let chosen = info.idx.map { pick(els, $0) } ?? els.array()
			return chosen.compactMap { try? replaceHtmlText($0.html(), info) }
		}
		return nil
	}

	func elements(_ doc: Document, _ id: ExtractId) -> Elements? {
		guard let infos = queryMap[id] else { return nil }
		for info in infos {
			guard let els = select(doc, info.query) else { continue }
			guard let idx = info.idx else { return els }
			let chosen = pick(els, idx)
			if !chosen.isEmpty { return Elements(chosen) }
		}
		return nil
	}

	func firstElement(_ doc: Document, _ id: ExtractId) -> Element? {
		guard let infos = queryMap[id] else { return nil }
		for info in infos {
			guard let els = select(doc, info.query) else { continue }
			if let e = pick(els, [info.idx?.first ?? 0]).first { return e }
		}
		return nil
	}

	private func postDates(_ doc: Document, _ id: ExtractId) -> [String]? {
		guard let infos = queryMap[id] else { return nil }
		for info in infos {
			guard let els = select(doc, info.query) else { continue }
			return els.array().map { info.replace((try? $0.html()) ?? "") }
		}
		return nil
	}

	private func replaceHtmlText(_ textIn: String, _ info: ExtractInfo?) throws -> String {
		var t = textIn.replaceAll("[\n|\r]", "").replaceAll("\t", " ")
		if let info { t = info.replace(t) }
		t = t.replaceAll("<br ?/?>", " ").replaceAll("<rt>.+?</rt>", "").replaceAll("<[^>]+>", "")
		return try SwiftSoup.parse(t).text()
	}

	/// Remembers each chapter's list-page date; returns chapters whose date didn't change.
	private func createNoUpdateUrls(_ updateInfoFile: URL, _ urlString: String, _ listBaseUrl: String, _ contentsUpdate: String?, _ hrefs: Elements, _ updates: Elements) -> Set<String>? {
		guard hrefs.size() == updates.size() else { return nil }
		var previous: [String: String] = [:]
		for line in (try? TextIO.readLines(updateInfoFile)) ?? [] {
			let idx = line.indexOf("\t")
			if idx > 0 { previous[line.jsub(0, idx)] = line.jsub(idx + 1) }
		}
		var out = ""
		if let contentsUpdate { out += urlString + "\t" + contentsUpdate + "\n" }
		for (i, update) in updates.array().enumerated() {
			out += ((try? hrefs.get(i).attr("href")) ?? "") + "\t" + ((try? update.html()) ?? "").replacingOccurrences(of: "\n", with: " ") + "\n"
		}
		try? out.write(to: updateInfoFile, atomically: true, encoding: .utf8)

		var noUpdate = Set<String>()
		for (i, href) in hrefs.array().enumerated() {
			let hrefString = (try? href.attr("href")) ?? ""
			guard !hrefString.isEmpty else { continue }
			let html = ((try? updates.get(i).html()) ?? "").replacingOccurrences(of: "\n", with: " ")
			if previous[hrefString] == html {
				noUpdate.insert(hrefString.hasPrefix("http") ? hrefString : (hrefString.hasPrefix("/") ? baseUri : listBaseUrl) + hrefString)
			}
		}
		return noUpdate
	}

	// MARK: - HTTP

	private func request(_ url: URL, referer: String? = nil) -> URLRequest {
		var r = URLRequest(url: url)
		if !options.userAgent.isEmpty { r.setValue(options.userAgent, forHTTPHeaderField: "User-Agent") }
		if let ua = queryMap[.USER_AGENT]?.first?.query { r.setValue(ua, forHTTPHeaderField: "User-Agent") }
		if let cookie = queryMap[.COOKIE]?.first?.query { r.setValue(cookie, forHTTPHeaderField: "Cookie") }
		if let referer { r.setValue(referer, forHTTPHeaderField: "Referer") }
		return r
	}

	private func cacheFile(_ urlString: String, _ file: URL, referer: String?) async throws {
		guard let url = URL(string: urlString) else { throw URLError(.badURL) }
		let fm = FileManager.default
		var isDir: ObjCBool = false
		if fm.fileExists(atPath: file.path, isDirectory: &isDir), isDir.boolValue { try? fm.removeItem(at: file) }
		try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
		let (data, response) = try await session.data(for: request(url, referer: referer))
		if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
			throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)"])
		}
		try data.write(to: file)
	}

	/// Decodes HTML using its BOM or <meta charset>, like Jsoup.parse(File, null).
	private func parseHTML(_ file: URL, baseUri: String) throws -> Document {
		let data = try Data(contentsOf: file)
		return try SwiftSoup.parse(Self.decodeHTML(data), baseUri)
	}

	static func decodeHTML(_ data: Data) -> String {
		if data.starts(with: [0xEF, 0xBB, 0xBF]) { return String(decoding: data.dropFirst(3), as: UTF8.self) }
		let head = String(decoding: data.prefix(4096), as: UTF8.self).lowercased()
		var charset = "utf-8"
		if let r = head.range(of: "charset=") {
			charset = String(head[r.upperBound...].drop(while: { $0 == "\"" || $0 == "'" }).prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
		}
		switch charset {
		case "shift_jis", "shift-jis", "sjis", "x-sjis", "windows-31j", "cp932", "ms932":
			return MS932Decoder.shared.decode(data)
		case "euc-jp", "x-euc-jp":
			return String(data: data, encoding: .japaneseEUC) ?? String(decoding: data, as: UTF8.self)
		default:
			return String(decoding: data, as: UTF8.self)
		}
	}
}
