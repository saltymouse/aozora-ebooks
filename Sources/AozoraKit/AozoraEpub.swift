import Foundation
import CoreGraphics

/// A book scanned and ready to convert. The app can edit the metadata, cover and
/// TOC selection (what the Java "変換前確認" dialog did) before calling `convert`.
public final class PreparedBook: @unchecked Sendable {
	public let srcFile: URL
	public let ext: String
	/// Index of the text inside an archive with several .txt files.
	public let textIndex: Int
	public let bookInfo: BookInfo
	public let imageInfoReader: ImageInfoReader
	let lines: [String]?

	public var title: String {
		get { bookInfo.title ?? "" }
		set { bookInfo.title = newValue }
	}
	public var creator: String {
		get { bookInfo.creator ?? "" }
		set { bookInfo.creator = newValue }
	}
	public var titleAs: String? {
		get { bookInfo.titleAs }
		set { bookInfo.titleAs = newValue?.isEmpty == true ? nil : newValue }
	}
	public var creatorAs: String? {
		get { bookInfo.creatorAs }
		set { bookInfo.creatorAs = newValue?.isEmpty == true ? nil : newValue }
	}
	public var publisher: String? {
		get { bookInfo.publisher }
		set { bookInfo.publisher = newValue?.isEmpty == true ? nil : newValue }
	}
	public var isImageOnly: Bool { bookInfo.imageOnly }
	/// TOC candidates; remove or rename via `applyToc`.
	public var tocEntries: [ChapterLineInfo] { bookInfo.chapterLineInfoList }
	/// Number of illustrations available as cover candidates.
	public var illustrationCount: Int { imageInfoReader.countImageFileNames }

	init(srcFile: URL, ext: String, textIndex: Int, bookInfo: BookInfo, imageInfoReader: ImageInfoReader, lines: [String]?) {
		self.srcFile = srcFile
		self.ext = ext
		self.textIndex = textIndex
		self.bookInfo = bookInfo
		self.imageInfoReader = imageInfoReader
		self.lines = lines
	}

	/// Keeps only the selected TOC lines, renaming them (Java confirm dialog `convert()`).
	public func applyToc(_ entries: [(lineNum: Int, selected: Bool, name: String)]) {
		for e in entries {
			guard let info = bookInfo.getChapterLineInfo(e.lineNum) else { continue }
			if e.selected { info.chapterName = e.name } else { bookInfo.removeChapterLineInfo(info.lineNum) }
		}
	}

	/// The current cover as an image: edited image, chosen illustration, or cover file.
	public func coverPreview() -> CGImage? {
		if let image = bookInfo.coverImage { return image }
		if bookInfo.coverImageIndex >= 0, let image = imageInfoReader.image(bookInfo.coverImageIndex) { return image }
		if let file = bookInfo.coverFileName, !file.isEmpty { return ImageUtils.load(file) }
		return nil
	}

	/// Re-reads title/author from the text with another layout (confirm sheet "再取得").
	public func reloadTitle(_ titleType: TitleType, pubFirst: Bool) {
		bookInfo.reloadMetadata(titleType, pubFirst)
	}

	public enum Cover {
		case none
		case illustration(Int)
		case file(String)
		/// A cropped/edited image. `keepOriginal` leaves the source illustration in the body
		/// (Java "元画像出力"); otherwise it moves to the cover.
		case edited(CGImage, keepOriginal: Bool)
	}

	public func setCover(_ cover: Cover) {
		switch cover {
		case .none:
			bookInfo.coverImage = nil
			bookInfo.coverFileName = nil
			bookInfo.coverImageIndex = -1
		case .illustration(let i):
			bookInfo.coverImage = nil
			bookInfo.coverFileName = nil
			bookInfo.coverImageIndex = i
		case .file(let f):
			bookInfo.coverImage = nil
			bookInfo.coverFileName = f
			bookInfo.coverImageIndex = -1
		case .edited(let image, let keepOriginal):
			bookInfo.coverImage = image
			bookInfo.coverFileName = nil
			if keepOriginal { bookInfo.coverImageIndex = -1 }
		}
	}
}

/// Converts Aozora Bunko text (txt/zip/txtz/rar) and image archives (zip/cbz/rar) to EPUB 3.
public final class AozoraEpub {
	public let settings: ConversionSettings
	public let log: Log
	let templateDirectory: URL
	let gaijiDirectory: URL
	let replaceFile: URL?

	private let writer: EpubWriter
	private let imageWriter: EpubImageWriter
	private let converter: AozoraConverter
	private var canceled = false

	public static let supportedExtensions = ["txt", "txtz", "zip", "cbz", "rar"]

	public init(settings: ConversionSettings, log: Log = Log(),
	            templateDirectory: URL = AozoraResources.templateDirectory,
	            gaijiDirectory: URL = AozoraResources.gaijiDirectory,
	            replaceFile: URL? = nil) {
		self.settings = settings
		self.log = log
		self.templateDirectory = templateDirectory
		self.gaijiDirectory = gaijiDirectory
		self.replaceFile = replaceFile
		writer = EpubWriter(templatePath: templateDirectory, log: log)
		imageWriter = EpubImageWriter(templatePath: templateDirectory, log: log)
		converter = AozoraConverter(writer: writer, log: log, replaceFile: replaceFile, gaijiDirectory: gaijiDirectory)
		imageWriter.gaijiFontDirectory = gaijiDirectory
		applySettings()
	}

	public func cancel() {
		canceled = true
		converter.cancel()
		writer.cancel()
		imageWriter.cancel()
	}

	/// Java `convertFiles`: copies GUI settings into the writer and converter.
	private func applySettings() {
		let s = settings
		var p = WriterParams()
		p.dispW = s.dispW
		p.dispH = s.dispH
		p.coverW = s.coverW
		p.coverH = s.coverH
		p.maxImageW = s.resizeW ? s.resizeNumW : 0
		p.maxImageH = s.resizeH ? s.resizeNumH : 0
		p.singlePageSizeW = s.singlePageSizeW
		p.singlePageSizeH = s.singlePageSizeH
		p.singlePageWidth = s.singlePageWidth
		p.imageScale = s.imageScaleChecked ? s.imageScale : 0
		if s.imageFloat {
			p.imageFloatType = s.imageFloatType + 1
			p.imageFloatW = s.imageFloatW
			p.imageFloatH = s.imageFloatH
		}
		p.jpegQuality = Float(s.jpegQuality) / 100
		p.gamma = s.gamma ? s.gammaValue : 1
		if s.autoMargin {
			p.autoMarginLimitH = s.autoMarginLimitH
			p.autoMarginLimitV = s.autoMarginLimitV
			p.autoMarginWhiteLevel = s.autoMarginWhiteLevel
			p.autoMarginPadding = s.autoMarginPadding
			p.autoMarginNombre = s.autoMarginNombre
			p.autoMarginNombreSize = s.autoMarginNombreSize * 0.01
		} else {
			p.autoMarginWhiteLevel = 0
		}
		p.rotateAngle = s.rotateImage == 1 ? 90 : s.rotateImage == 2 ? -90 : 0
		p.imageSizeType = s.imageSizeType == SectionInfo.imageSizeTypeAuto ? SectionInfo.imageSizeTypeAuto : SectionInfo.imageSizeTypeAspect
		p.fitImage = s.fitImage
		p.isSvgImage = s.svgImage
		p.navNest = s.navNest
		p.ncxNest = s.ncxNest
		let pageUnit = s.pageMarginUnit == 0 ? "em" : "%"
		p.pageMargin = s.pageMargin.map { $0 + pageUnit }
		let bodyUnit = s.bodyMarginUnit == 0 ? "em" : "%"
		p.bodyMargin = s.bodyMargin.map { $0 + bodyUnit }
		p.lineHeight = s.lineHeight
		p.fontSize = s.fontSize
		p.boldUseGothic = s.boldUseGothic
		p.gothicUseBold = s.gothicUseBold
		p.isKindle = s.ext.hasPrefix(".mobi")
		writer.params = p
		// Java only called setImageParam on its image-only writer: styles and TOC nesting
		// stay at the writer's field defaults there.
		var ip = p
		let d = WriterParams()
		ip.navNest = d.navNest; ip.ncxNest = d.ncxNest
		ip.pageMargin = d.pageMargin; ip.bodyMargin = d.bodyMargin
		ip.lineHeight = 0; ip.fontSize = d.fontSize
		ip.boldUseGothic = d.boldUseGothic; ip.gothicUseBold = d.gothicUseBold
		imageWriter.params = ip

		let c = converter
		c.noIllust = s.noIllust
		c.withMarkId = s.markId
		c.autoYoko = s.autoYoko
		c.autoYokoNum1 = s.autoYokoNum1
		c.autoYokoNum3 = s.autoYokoNum3
		c.autoYokoEQ1 = s.autoYokoEQ1
		c.dakutenType = s.dakutenType
		c.printIvsBMP = s.ivsBMP
		c.printIvsSSP = s.ivsSSP
		c.spaceHyphenation = s.spaceHyphenation
		c.chukiRuby = s.chukiRuby == 1
		c.chukiKogaki = s.chukiRuby == 2
		c.commentPrint = s.commentPrint
		c.commentConvert = s.commentConvert
		c.imageFloatPage = s.imageFloatPage
		c.imageFloatBlock = s.imageFloatBlock
		c.setRemoveEmptyLine(s.removeEmptyLine, s.maxEmptyLine)
		c.forceIndent = s.forceIndent
		if s.pageBreak {
			c.setForcePageBreak(s.pageBreakSize * 1024,
			                    s.pageBreakEmpty ? s.pageBreakEmptyLine : 0, s.pageBreakEmpty ? s.pageBreakEmptySize * 1024 : 0,
			                    s.pageBreakChapter ? 1 : 0, s.pageBreakChapter ? s.pageBreakChapterSize * 1024 : 0)
		}
		c.setChapterLevel(maxLength: s.maxChapterNameLength, excludeSeqencialChapter: s.chapterExclude, useNextLineChapterName: s.chapterUseNextLine,
		                  section: s.chapterSection, h: s.chapterH, h1: s.chapterH1, h2: s.chapterH2, h3: s.chapterH3,
		                  sameLineChapter: s.sameLineChapter, chapterName: s.chapterName,
		                  numOnly: s.chapterNumOnly, numTitle: s.chapterNumTitle, numParen: s.chapterNumParen, numParenTitle: s.chapterNumParenTitle,
		                  pattern: s.chapterPattern ? s.chapterPatternText.trimmingCharacters(in: .whitespaces) : "")
	}

	// MARK: - Prepare

	/// Scans a file. Archives with several .txt files yield one book per text.
	/// - Parameter encoding: overrides the settings (web downloads are UTF-8).
	public func prepare(_ srcFile: URL, encoding: TextEncoding? = nil) throws -> [PreparedBook] {
		canceled = false
		let ext = srcFile.pathExtension.lowercased()
		guard Self.supportedExtensions.contains(ext) else {
			throw ConversionError.unsupported(srcFile.lastPathComponent)
		}
		var txtCount = 1
		var imageOnly = false
		if ext == "zip" || ext == "txtz" || ext == "rar" {
			txtCount = try ArchiveReader(url: srcFile).textEntryNames().count
			if txtCount == 0 { txtCount = 1; imageOnly = true }
		} else if ext == "cbz" {
			imageOnly = true
		}
		var books: [PreparedBook] = []
		for i in 0..<txtCount {
			if canceled { break }
			if let book = try prepare(srcFile, ext: ext, textIndex: i, imageOnly: imageOnly, encoding: encoding ?? settings.encoding) {
				books.append(book)
			}
		}
		return books
	}

	private func prepare(_ srcFile: URL, ext: String, textIndex: Int, imageOnly: Bool, encoding: TextEncoding) throws -> PreparedBook? {
		let s = settings
		var coverImageIndex = -1
		var coverFileName: String?
		switch s.cover {
		case .firstIllustration: coverFileName = ""; coverImageIndex = 0
		case .sameNameImage: coverFileName = Self.sameCoverFileName(srcFile)
		case .none: coverFileName = nil
		case .file(let f): coverFileName = f
		}

		let isFile = ext == "txt"
		let reader = ImageInfoReader(isFile: isFile, srcFile: srcFile)
		if !isFile {
			do { try reader.loadArchiveImageInfos(srcFile, addFileName: imageOnly, log: log) }
			catch { log.error("\(error)") }
		}

		var bookInfo: BookInfo
		var lines: [String]? = nil
		if !imageOnly {
			guard let (text, entryName) = try readText(srcFile, ext: ext, textIndex: textIndex, reader: reader, encoding: encoding) else {
				log.error("書籍の情報が取得できませんでした")
				return nil
			}
			lines = text
			bookInfo = converter.getBookInfo(srcFile, text, reader, s.titleType, s.pubFirst)
			bookInfo.textEntryName = entryName
		} else {
			log.println("画像のみのePubファイルを生成します")
			bookInfo = BookInfo(srcFile)
			bookInfo.imageOnly = true
			if reader.countImageFileInfos == 0 {
				log.error("画像がありませんでした")
				return nil
			}
			reader.sortImageFileNames()
		}
		if !isFile && !imageOnly {
			if reader.countImageFileNames == 0 { coverImageIndex = -1 }
			reader.addNoNameImageFileName()
		}

		bookInfo.insertCoverPage = s.coverPage
		bookInfo.insertTocPage = s.tocPage
		bookInfo.insertCoverPageToc = s.coverPageToc
		bookInfo.insertTitleToc = s.titleToc
		if !bookInfo.insertTitleToc && bookInfo.titleLine >= 0 { bookInfo.removeChapterLineInfo(bookInfo.titleLine) }
		bookInfo.tocVertical = s.tocVertical
		bookInfo.vertical = s.vertical
		bookInfo.titlePageType = s.titlePageWrite ? s.titlePage : .none

		if coverFileName == "" && !imageOnly {
			if s.maxCoverLine > 0 && (bookInfo.firstImageLineNum == -1 || bookInfo.firstImageLineNum >= s.maxCoverLine) {
				coverImageIndex = -1
				coverFileName = nil
			} else {
				coverImageIndex = bookInfo.firstImageIdx
			}
		}
		bookInfo.coverFileName = coverFileName
		bookInfo.coverImageIndex = coverImageIndex

		let fileTitle = BookInfo.fileTitleCreator(srcFile.lastPathComponent)
		if s.useFileName {
			bookInfo.title = fileTitle.title ?? ""
			bookInfo.creator = fileTitle.creator ?? ""
		} else if (bookInfo.title ?? "").isEmpty {
			bookInfo.title = fileTitle.title ?? ""
			if (bookInfo.creator ?? "").isEmpty { bookInfo.creator = fileTitle.creator ?? "" }
		}
		// Java's confirm dialog found cover.png/jpg next to the text when nothing else was set.
		if bookInfo.coverFileName == nil && bookInfo.coverImageIndex < 0 && s.confirm {
			let dir = srcFile.deletingLastPathComponent()
			for name in ["cover.png", "cover.jpg", "cover.jpeg"] where FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) {
				bookInfo.coverFileName = dir.appendingPathComponent(name).path
				break
			}
		}
		return PreparedBook(srcFile: srcFile, ext: ext, textIndex: textIndex, bookInfo: bookInfo, imageInfoReader: reader, lines: lines)
	}

	/// Reads the text of a .txt file or the n-th .txt entry of an archive.
	private func readText(_ srcFile: URL, ext: String, textIndex: Int, reader: ImageInfoReader, encoding: TextEncoding) throws -> ([String], String?)? {
		if ext == "txt" {
			return (TextIO.lines(try Data(contentsOf: srcFile), encoding), nil)
		}
		var idx = textIndex
		var found: ([String], String?)? = nil
		try ArchiveReader(url: srcFile).forEach { entry, read in
			guard !entry.isDirectory, entry.name.lowercased().hasSuffix(".txt") else { return true }
			if idx == 0 {
				reader.setArchiveTextEntry(entry.name)
				found = (TextIO.lines(read(), encoding), entry.name)
				return false
			}
			idx -= 1
			return true
		}
		if found == nil { log.error("\(ext)内にtxtファイルがありません: \(srcFile.lastPathComponent)") }
		return found
	}

	// MARK: - Convert

	/// Output file for a book (Java `getOutFile`).
	public func outputURL(for book: PreparedBook, in dstDirectory: URL? = nil, ext: String? = nil) -> URL {
		URL(fileURLWithPath: outputPath(for: book, in: dstDirectory, ext: ext))
	}

	/// The output path as a String. URLs normalize file names to NFD; this keeps the title as written.
	public func outputPath(for book: PreparedBook, in dstDirectory: URL? = nil, ext: String? = nil) -> String {
		let dst = dstDirectory ?? book.srcFile.deletingLastPathComponent()
		var outExt = ext ?? settings.ext
		if outExt.hasPrefix(".mobi") { outExt = ".epub" }
		if outExt.isEmpty { outExt = ".epub" }
		let info = book.bookInfo
		var name: String
		if settings.autoFileName && (info.creator != nil || info.title != nil) {
			name = ""
			if let creator = info.creator, creator.jlen > 0 {
				var str = creator.replaceAll("[\\\\|\\/|\\:|\\*|\\?|\\<|\\>|\\||\\\"|\t]", "")
				if str.jlen > 64 { str = str.jsub(0, 64) }
				name += "[" + str + "] "
			}
			if let title = info.title {
				name += title.replaceAll("[\\\\|\\/|\\:|\\*|\\!|\\?|\\<|\\>|\\||\\\"|\t]", "")
			}
			let full = dst.path + "/" + name
			if full.jlen > 250 { name = full.jsub(0, 250).jsub(dst.path.jlen + 1) }
		} else {
			name = book.srcFile.lastPathComponent.replaceFirst("\\.[^\\.]+$", "")
		}
		return dst.path + "/" + name + outExt
	}

	/// Writes the EPUB. Returns the output file (and the .mobi path if kindlegen ran).
	@discardableResult
	public func convert(_ book: PreparedBook, to outFile: URL? = nil, dstDirectory: URL? = nil,
	                    progress: ((Double) -> Void)? = nil) throws -> URL {
		canceled = false
		let outPath = outFile?.path ?? outputPath(for: book, in: dstDirectory)
		let out = URL(fileURLWithPath: outPath)
		let wantsMobi = settings.ext.hasPrefix(".mobi")
		var kindlegen: URL? = nil
		if wantsMobi {
			guard let k = KindleGen.locate() else { throw ConversionError.kindlegenMissing }
			kindlegen = k
		}
		if !settings.overWrite && FileManager.default.fileExists(atPath: outPath) {
			log.error("変換中止: " + book.srcFile.path)
			log.error("ファイルが存在します: " + out.path)
			throw ConversionError.exists(out)
		}

		let w = book.bookInfo.imageOnly ? imageWriter : writer
		let bookInfo = book.bookInfo
		let total: Int
		if bookInfo.imageOnly { total = book.imageInfoReader.countImageFileInfos * 11 }
		else if book.ext == "txt" { total = bookInfo.totalLineNum / 10 + book.imageInfoReader.countImageFileNames * 10 }
		else { total = bookInfo.totalLineNum / 10 + book.imageInfoReader.countImageFileInfos * 10 }
		w.setProgressTotal(total)
		w.progress = { done, total in progress?(Double(done) / Double(max(1, total))) }

		let start = Date()
		log.println("変換開始 : " + book.srcFile.path)
		converter.vertical = bookInfo.vertical
		// Write under a temporary name, then rename: Foundation file APIs decompose names (NFD),
		// POSIX rename keeps the precomposed (NFC) title the Java app produced.
		let writeURL = out.deletingLastPathComponent().appendingPathComponent(".aozora-\(UUID().uuidString).epub")
		// the chosen output folder may have been moved or deleted since
		try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
		do {
			try w.write(converter, book.lines, book.srcFile, book.ext, writeURL, bookInfo, book.imageInfoReader)
		} catch {
			try? FileManager.default.removeItem(at: writeURL)
			throw error
		}
		bookInfo.coverImage = nil
		if canceled {
			try? FileManager.default.removeItem(at: writeURL)
			throw ConversionError.canceled
		}
		if !wantsMobi { try Self.rename(writeURL.path, to: outPath) }
		log.println(String(format: "変換完了[%.1fs] : ", Date().timeIntervalSince(start)) + out.path)

		if let kindlegen {
			let mobi = try KindleGen.run(kindlegen, epub: writeURL, log: log)
			let finalMobi = (outPath as NSString).deletingPathExtension + ".mobi"
			try Self.rename(mobi.path, to: finalMobi)
			if settings.ext.hasSuffix(".epub") {
				try Self.rename(writeURL.path, to: outPath)
			} else {
				try? FileManager.default.removeItem(at: writeURL)
			}
			return URL(fileURLWithPath: finalMobi)
		}
		return out
	}

	/// rename(2), replacing any existing file, with the path bytes exactly as given (NFC).
	static func rename(_ from: String, to: String) throws {
		let result = from.withCString { src in to.withCString { dst in Darwin.rename(src, dst) } }
		if result != 0 { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: to]) }
	}

	/// An image named like the input file (png/jpg/jpeg in three cases).
	public static func sameCoverFileName(_ srcFile: URL) -> String? {
		let base = srcFile.deletingPathExtension().path + "."
		for ext in ["png", "jpg", "jpeg", "PNG", "JPG", "JPEG", "Png", "Jpg", "Jpeg"] where FileManager.default.fileExists(atPath: base + ext) {
			return base + ext
		}
		return nil
	}
}

public enum ConversionError: LocalizedError {
	case unsupported(String)
	case exists(URL)
	case kindlegenMissing
	case kindlegenFailed(String)
	case canceled
	case badURL(String)
	case noSiteDefinition(String)
	case notAozoraCard(String)
	case download(String, String)
	case noText(String)

	public var errorDescription: String? {
		switch self {
		case .unsupported(let name): return String(localized: "\(name) isn't a format this app converts (txt, txtz, zip, cbz, rar).", bundle: .module)
		case .exists(let url): return String(localized: "\(url.lastPathComponent) already exists and “Replace files that already exist” is off.", bundle: .module)
		case .kindlegenMissing: return String(localized: "This preset makes .mobi files, which need Amazon's kindlegen, and it isn't installed. Switch to EPUB (Kindle accepts EPUB through Send to Kindle), or install Kindle Previewer, which includes kindlegen.", bundle: .module)
		case .kindlegenFailed(let msg): return String(localized: "kindlegen failed: \(msg)", bundle: .module)
		case .canceled: return String(localized: "Canceled.", bundle: .module)
		case .badURL(let s): return String(localized: "“\(s)” isn't a web address.", bundle: .module)
		case .noSiteDefinition(let host): return String(localized: "\(host) isn't a supported site. Web novels work from: \(WebNovelDownloader.supportedHosts().joined(separator: ", ")). For Aozora Bunko, use a work's card page (図書カード) or its .zip link.", bundle: .module)
		case .notAozoraCard(let s): return String(localized: "Couldn't find a text download on \(s). Open the work's card page (図書カード, the page with “ファイルのダウンロード”) and use that link.", bundle: .module)
		case .download(let s, let why): return String(localized: "Couldn't download \(s): \(why)", bundle: .module)
		case .noText(let name): return String(localized: "\(name) has no Aozora text to convert.", bundle: .module)
		}
	}
}

/// Finds and runs Amazon's kindlegen for .mobi output.
public enum KindleGen {
	public static func locate() -> URL? {
		let fm = FileManager.default
		var candidates = [
			"/Applications/Kindle Previewer 3.app/Contents/lib/fc/bin/kindlegen",
			"/Applications/Kindle Previewer.app/Contents/lib/fc/bin/kindlegen",
			NSHomeDirectory() + "/Library/Application Support/Aozora Ebooks/kindlegen",
		]
		for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin").split(separator: ":") {
			candidates.append(String(dir) + "/kindlegen")
		}
		return candidates.first { fm.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
	}

	static func run(_ kindlegen: URL, epub: URL, log: Log) throws -> URL {
		log.println("kindlegenを実行します : " + kindlegen.lastPathComponent + " \"" + epub.path + "\"")
		let p = Process()
		p.executableURL = kindlegen
		p.arguments = ["-locale", "en", "-verbose", epub.path]
		let pipe = Pipe()
		p.standardOutput = pipe
		p.standardError = pipe
		try p.run()
		let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
		p.waitUntilExit()
		let mobi = epub.deletingPathExtension().appendingPathExtension("mobi")
		guard FileManager.default.fileExists(atPath: mobi.path) else {
			throw ConversionError.kindlegenFailed(output.split(separator: "\n").last.map(String.init) ?? "exit \(p.terminationStatus)")
		}
		log.println("kindlegen変換完了")
		return mobi
	}
}

// MARK: - Web

extension AozoraEpub {
	/// Settings the Java app switched to while converting downloaded web text.
	public static func webSettings(_ s: ConversionSettings) -> ConversionSettings {
		var w = s
		w.encoding = .utf8
		w.titleType = .titleAuthor
		w.useFileName = false
		w.commentPrint = true
		w.commentConvert = true
		// converted.png sits next to converted.txt: "same name" picks it up
		if case .firstIllustration = s.cover { w.cover = .sameNameImage }
		return w
	}

	/// Downloads a URL and returns a local file ready for `prepare`: an archive (a zip/txtz/rar
	/// link or an Aozora Bunko card page, saved into `downloadDirectory`) or a web novel's converted.txt.
	/// Returns nil when a web novel had nothing new to convert; throws when the URL can't be used.
	public static func fetch(_ urlString: String, settings: ConversionSettings, cacheDirectory: URL, downloadDirectory: URL,
	                         log: Log, downloader: ((WebNovelDownloader) -> Void)? = nil) async throws -> URL? {
		guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)), let host = url.host() else {
			throw ConversionError.badURL(urlString)
		}
		var archiveURL: URL? = nil
		let ext = url.pathExtension.lowercased()
		if ["zip", "txtz", "rar"].contains(ext) {
			archiveURL = url
		} else if host.hasSuffix("aozora.gr.jp") {
			archiveURL = try await aozoraCardArchive(url, log: log)
		}
		if let archiveURL {
			let dst = downloadDirectory.appendingPathComponent(archiveURL.lastPathComponent)
			log.println("出力先にダウンロードします : " + dst.path)
			let (data, response) = try await URLSession.shared.data(from: archiveURL)
			if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
				throw ConversionError.download(archiveURL.absoluteString, "HTTP \(http.statusCode)")
			}
			try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
			try data.write(to: dst)
			return dst
		}
		log.println("--------")
		log.println(urlString + " を読み込みます")
		guard let web = WebNovelDownloader(url: urlString, log: log) else {
			throw ConversionError.noSiteDefinition(host)
		}
		downloader?(web)
		guard let result = try await web.download(urlString, cacheDirectory: cacheDirectory, options: WebOptions(settings)) else {
			if web.updated {
				log.error(urlString + " は変換できませんでした")
				throw ConversionError.download(urlString, String(localized: "The page didn't contain a title or chapter list the site definition could read.", bundle: .module))
			}
			log.warn(urlString + " の変換をスキップしました")
			return nil
		}
		return result.textFile
	}

	/// The ruby-text zip linked from an Aozora Bunko card page (図書カード).
	static func aozoraCardArchive(_ url: URL, log: Log) async throws -> URL {
		let (data, _) = try await URLSession.shared.data(from: url)
		let html = WebNovelDownloader.decodeHTML(data)
		let links = JPattern.compile("href=[\"']([^\"']+\\.zip)[\"']", caseInsensitive: true).matcher(html)
		var zips: [String] = []
		while links.find() { if let h = links.group(1) { zips.append(h) } }
		// prefer the ruby edition (xxx_ruby_nnnn.zip) over plain text
		guard let href = zips.first(where: { $0.contains("_ruby_") }) ?? zips.first,
		      let zip = URL(string: href, relativeTo: url)?.absoluteURL else {
			throw ConversionError.notAozoraCard(url.absoluteString)
		}
		log.println("図書カードからテキストを取得します : " + zip.absoluteString)
		return zip
	}

	/// Default cache for web downloads: ~/Library/Caches/Aozora Ebooks/web
	public static var defaultWebCache: URL {
		FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("Aozora Ebooks", isDirectory: true).appendingPathComponent("web", isDirectory: true)
	}
}
