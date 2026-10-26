import Foundation
import CoreGraphics
import CryptoKit
import ZIPFoundation

/// Image, layout and style parameters for the writer (Java `setImageParam`, `setTocParam`, `setStyles`).
struct WriterParams {
	var dispW = 600
	var dispH = 800
	var coverW = 600
	var coverH = 800
	var maxImageW = 0
	var maxImageH = 0
	var maxImagePixels = 0
	var singlePageSizeW = 400
	var singlePageSizeH = 600
	var singlePageWidth = 550
	var imageSizeType = SectionInfo.imageSizeTypeHeight
	var fitImage = true
	var isSvgImage = false
	var rotateAngle = 0
	var imageScale: Float = 1
	var imageFloatType = 0
	var imageFloatW = 0
	var imageFloatH = 0
	var jpegQuality: Float = 0.8
	var gamma: Float = 1
	var autoMarginLimitH = 0
	var autoMarginLimitV = 0
	var autoMarginWhiteLevel = 100
	var autoMarginPadding: Float = 0
	var autoMarginNombre = 0
	var autoMarginNombreSize: Float = 0.03
	var navNest = false
	var ncxNest = false
	var pageMargin = ["0", "0", "0", "0"]
	var bodyMargin = ["0", "0", "0", "0"]
	var lineHeight: Float = 1.8
	var fontSize = 100
	var boldUseGothic = true
	var gothicUseBold = true
	var isKindle = false
}

/// Builds the EPUB zip: sections split at page breaks into xhtml/0001.xhtml…,
/// images renamed to images/0001.jpg… (port of `Epub3Writer`).
class EpubWriter {
	static let opsPath = "OPS/"
	static let imagesPath = "images/"
	static let cssPath = "css/"
	static let xhtmlPath = "xhtml/"

	var params = WriterParams()
	let templatePath: URL
	let log: Log
	/// Folder of single-glyph fonts (set by the converter).
	var gaijiFontDirectory = AozoraResources.gaijiDirectory
	/// Called with (done, total) work units.
	var progress: ((Int, Int) -> Void)?
	var canceled = false

	var archive: Archive!
	var sectionIndex = 0
	var imageIndex = 0
	var sectionInfos: [SectionInfo] = []
	var chapterInfos: [ChapterInfo] = []
	var vecGaijiInfo: [GaijiInfo] = []
	var gaijiNameSet = Set<String>()
	var imageInfos: [ImageInfo] = []
	var outImageFileNames = Set<String>()
	var velocityContext = VelocityContext()
	var bookInfo: BookInfo!
	var imageInfoReader: ImageInfoReader!

	private var sectionBuffer = ""
	private var currentSectionPath: String?
	private var progressDone = 0
	private var progressTotal = 1
	private var templates: [String: VelocityTemplate] = [:]

	init(templatePath: URL = AozoraResources.templateDirectory, log: Log) {
		self.templatePath = templatePath
		self.log = log
	}

	var templateFiles: [String] {
		let v = bookInfo?.vertical ?? false
		let prefix = Self.opsPath + Self.cssPath + (v ? "vertical" : "horizontal")
		return ["META-INF/container.xml", prefix + "_middle.css", prefix + "_image.css", prefix + "_font.css", prefix + ".css"]
	}

	func cancel() { canceled = true }

	// MARK: Zip helpers

	func addEntry(_ path: String, _ data: Data, compressed: Bool = true) throws {
		try archive.addEntry(with: path, type: .file, uncompressedSize: Int64(data.count),
		                     compressionMethod: compressed ? .deflate : .none) { position, size in
			data.subdata(in: Int(position)..<Int(position) + size)
		}
	}

	func addEntry(_ path: String, _ text: String) throws { try addEntry(path, Data(text.utf8)) }

	/// Copies a template file, preferring `<dir>_custom/<file>` when present.
	private func writeFile(_ fileName: String) throws {
		var file = templatePath.appendingPathComponent(fileName)
		let idx = fileName.lastIndexOf("/")
		if idx > 0 {
			let custom = templatePath.appendingPathComponent(fileName.jsub(0, idx) + "_custom/" + fileName.jsub(idx + 1))
			if FileManager.default.fileExists(atPath: custom.path) { file = custom }
		}
		try addEntry(fileName, try Data(contentsOf: file))
	}

	func template(_ relativePath: String) throws -> VelocityTemplate {
		if let t = templates[relativePath] { return t }
		let t = try VelocityTemplate(contentsOf: templatePath.appendingPathComponent(relativePath))
		templates[relativePath] = t
		return t
	}

	func merge(_ relativePath: String) throws -> String {
		try template(relativePath).render(velocityContext)
	}

	// MARK: Progress

	func setProgressTotal(_ total: Int) {
		progressTotal = max(1, total)
		progressDone = 0
		progress?(0, progressTotal)
	}
	func addProgress(_ n: Int) {
		progressDone = min(progressTotal, progressDone + n)
		progress?(progressDone, progressTotal)
	}
	func reportTextProgress(_ lineNum: Int) {
		progressDone = min(progressTotal, lineNum / 10)
		progress?(progressDone, progressTotal)
	}

	// MARK: Write

	/// Writes the EPUB (Java `write`). Throws only for I/O failures; conversion problems are logged.
	func write(_ converter: AozoraConverter, _ lines: [String]?, _ srcFile: URL, _ srcExt: String, _ epubFile: URL, _ bookInfo: BookInfo, _ imageInfoReader: ImageInfoReader) throws {
		canceled = false
		self.bookInfo = bookInfo
		self.imageInfoReader = imageInfoReader
		sectionIndex = 0
		imageIndex = 0
		sectionInfos.removeAll()
		chapterInfos.removeAll()
		vecGaijiInfo.removeAll()
		gaijiNameSet.removeAll()
		imageInfos.removeAll()
		outImageFileNames.removeAll()
		velocityContext = VelocityContext()
		defer {
			self.archive = nil
			self.bookInfo = nil
			self.imageInfoReader = nil
		}

		let title = bookInfo.title ?? ""
		let creator = bookInfo.creator ?? ""
		if bookInfo.creator == "" { bookInfo.creator = nil }

		velocityContext.put("identifier", Self.nameUUID(title + "-" + creator))
		velocityContext.put("cover_name", "表紙")
		velocityContext.put("title", CharUtils.escapeHtml(title))
		if let titleAs = bookInfo.titleAs { velocityContext.put("titleAs", CharUtils.escapeHtml(titleAs)) }
		velocityContext.put("creator", CharUtils.escapeHtml(creator))
		if let creatorAs = bookInfo.creatorAs { velocityContext.put("creatorAs", CharUtils.escapeHtml(creatorAs)) }
		if let publisher = bookInfo.publisher { velocityContext.put("publisher", publisher) }
		velocityContext.put("bookInfo", bookInfo)
		velocityContext.put("modified", Self.modifiedFormat.string(from: bookInfo.modified))
		velocityContext.put("navNest", params.navNest)
		if params.isKindle { velocityContext.put("kindle", true) }
		if params.isSvgImage { velocityContext.put("svgImage", true) }
		velocityContext["pageMargin"] = .list(params.pageMargin.map { .string($0) })
		velocityContext["bodyMargin"] = .list(params.bodyMargin.map { .string($0) })
		velocityContext["lineHeight"] = .float(params.lineHeight)
		velocityContext.put("fontSize", params.fontSize)
		velocityContext.put("boldUseGothic", params.boldUseGothic)
		velocityContext.put("gothicUseBold", params.gothicUseBold)

		try? FileManager.default.removeItem(at: epubFile)
		archive = try Archive(url: epubFile, accessMode: .create, pathEncoding: nil)

		// mimetype first, stored uncompressed
		try addEntry("mimetype", try Data(contentsOf: templatePath.appendingPathComponent("mimetype")), compressed: false)
		for fileName in templateFiles { try writeFile(fileName) }

		var archivePathLength = 0
		if let entry = bookInfo.textEntryName { archivePathLength = entry.indexOf("/") + 1 }

		try writeSections(converter, lines, srcFile, srcExt)
		if canceled { return }

		velocityContext["vecGaijiInfo"] = .list(vecGaijiInfo.map { .object($0) })
		if bookInfo.vertical {
			try addEntry(Self.opsPath + Self.cssPath + "vertical_text.css", try merge(Self.opsPath + Self.cssPath + "vertical_text.vm"))
		} else {
			try addEntry(Self.opsPath + Self.cssPath + "horizontal_text.css", try merge(Self.opsPath + Self.cssPath + "horizontal_text.vm"))
		}

		// title page from template + metadata (after body so gaiji image order is kept)
		if !bookInfo.imageOnly && (bookInfo.titlePageType == .middle || bookInfo.titlePageType == .horizontal) {
			var vm = Self.opsPath + Self.xhtmlPath + "title_middle.vm"
			if bookInfo.titlePageType == .horizontal {
				converter.vertical = false
				vm = Self.opsPath + Self.xhtmlPath + "title_horizontal.vm"
			}
			let fields: [(String, String?)] = [
				("TITLE", bookInfo.titleText), ("SUBTITLE", bookInfo.subTitleText), ("ORGTITLE", bookInfo.orgTitleText),
				("SUBORGTITLE", bookInfo.subOrgTitleText), ("CREATOR", bookInfo.creatorText), ("SUBCREATOR", bookInfo.subCreatorText),
				("SERIES", bookInfo.seriesText), ("PUBLISHER", bookInfo.publisherText),
			]
			for (key, line) in fields {
				if let line { velocityContext.put(key, converter.convertTitleLineToEpub3(line)) }
			}
			try addEntry(Self.opsPath + Self.xhtmlPath + "title.xhtml", try merge(vm))
			velocityContext.put("title_page", true)
			if bookInfo.getChapterLineInfo(bookInfo.titleLine) != nil {
				chapterInfos.insert(ChapterInfo("title", nil, bookInfo.title, ChapterLineInfo.levelTitle), at: 0)
			}
		}
		if canceled { return }

		// cover
		var coverImageBytes: Data? = nil
		var coverImageInfo: ImageInfo? = nil
		if let coverFileName = bookInfo.coverFileName, coverFileName.jlen > 0 {
			for info in imageInfos { info.isCover = false }
			let data: Data?
			if coverFileName.hasPrefix("http"), let url = URL(string: coverFileName) {
				data = try? Data(contentsOf: url)
			} else {
				data = FileManager.default.contents(atPath: coverFileName)
			}
			if let data, let info = ImageInfo.read(data) {
				coverImageBytes = data
				var ext = info.ext
				if params.isKindle || ext == "jpeg" { ext = "jpg" }
				info.id = "0000"
				info.outFileName = "0000." + ext
				if !ext.matches("^(png|jpg|jpeg|gif)$") {
					log.println("表紙画像フォーマットエラー: " + coverFileName)
				} else {
					info.isCover = true
					imageInfos.insert(info, at: 0)
					coverImageInfo = info
				}
			} else {
				log.error("表紙画像取得エラー: " + coverFileName)
			}
		} else if let coverImage = bookInfo.coverImage {
			for info in imageInfos { info.isCover = false }
			var ext = "jpg"
			if let coverExt = bookInfo.coverExt { ext = coverExt }
			else if bookInfo.coverImageIndex > -1, let info = imageInfoReader.imageInfo(bookInfo.coverImageIndex) { ext = info.ext }
			if params.isKindle || ext == "jpeg" { ext = "jpg" }
			let info = ImageInfo(ext, coverImage.width, coverImage.height)
			info.id = "0000"
			info.outFileName = "0000." + ext
			info.isCover = true
			imageInfos.insert(info, at: 0)
			coverImageInfo = info
		} else if bookInfo.coverImageIndex > -1 && imageInfoReader.countImageFileNames > bookInfo.coverImageIndex && srcExt != "txt" {
			// archive image not referenced by the text
			var imageFileName = imageInfoReader.imageFileName(bookInfo.coverImageIndex)
			if let info = imageInfoReader.imageInfo(imageFileName) {
				imageFileName = imageFileName.jsub(archivePathLength)
				outImageFileNames.insert(imageFileName)
				for i in imageInfos { i.isCover = false }
				info.isCover = true
				if !imageInfos.contains(where: { $0 === info }) { imageInfos.append(info) }
			}
		}

		if bookInfo.insertCoverPage {
			var insertCoverInfo = coverImageInfo
			if insertCoverInfo == nil && bookInfo.coverImageIndex > -1 {
				insertCoverInfo = imageInfoReader.imageInfo(bookInfo.coverImageIndex)
				if let info = insertCoverInfo {
					info.isCover = true
					if !bookInfo.imageOnly && info.id == nil {
						imageIndex += 1
						let imageId = Self.format4(imageIndex)
						info.id = imageId
						info.outFileName = imageId + "." + (params.isKindle ? "jpg" : info.ext)
					}
				}
			}
			if let info = insertCoverInfo {
				let sectionInfo = SectionInfo("cover-page")
				if params.imageSizeType != SectionInfo.imageSizeTypeAuto {
					if Double(info.width) / Double(info.height) >= Double(params.coverW) / Double(params.coverH) { sectionInfo.imageFitW = true }
					else { sectionInfo.imageFitH = true }
				}
				velocityContext.put("sectionInfo", sectionInfo)
				velocityContext.put("coverImage", info)
				try addEntry(Self.opsPath + Self.xhtmlPath + "cover.xhtml", try merge(Self.opsPath + Self.xhtmlPath + "cover.vm"))
			} else {
				bookInfo.insertCoverPage = false
			}
		}

		velocityContext.put("sections", sectionInfos)
		velocityContext.put("images", imageInfos)
		try addEntry(Self.opsPath + "package.opf", try merge(Self.opsPath + "package.vm"))

		chapterInfos.removeAll { $0.chapterName == nil }
		if bookInfo.insertTitleToc && chapterInfos.count >= 2 {
			chapterInfos[0].chapterLevel = chapterInfos[1].chapterLevel
		}
		buildTocLevels()

		if !bookInfo.imageOnly {
			converter.vertical = bookInfo.tocVertical
			let spaceHyphenation = converter.spaceHyphenation
			converter.spaceHyphenation = 0
			for info in chapterInfos {
				var converted = CharUtils.escapeHtml(info.chapterName ?? "")
				if bookInfo.tocVertical { converted = converter.convertTcyText(converted) }
				info.chapterName = converted
			}
			converter.vertical = bookInfo.vertical
			converter.spaceHyphenation = spaceHyphenation
		}

		velocityContext.put("chapters", chapterInfos)
		try addEntry(Self.opsPath + Self.xhtmlPath + "nav.xhtml", try merge(Self.opsPath + Self.xhtmlPath + "xhtml_nav.vm"))
		try addEntry(Self.opsPath + "toc.ncx", try merge(Self.opsPath + "toc.ncx.vm"))
		if canceled { return }

		// bundled fonts (template/OPS/fonts) and gaiji fonts
		if !bookInfo.imageOnly {
			let fontsPath = templatePath.appendingPathComponent(Self.opsPath + "fonts")
			if let fonts = try? FileManager.default.contentsOfDirectory(at: fontsPath, includingPropertiesForKeys: nil) {
				for font in fonts { try addEntry(Self.opsPath + "fonts/" + font.lastPathComponent, try Data(contentsOf: font)) }
			}
		}
		for gaiji in vecGaijiInfo where FileManager.default.fileExists(atPath: gaiji.file.path) {
			try addEntry(Self.opsPath + "gaiji/" + gaiji.file.lastPathComponent, try Data(contentsOf: gaiji.file))
		}

		// cover image (edited or external file)
		if let info = coverImageInfo {
			var coverImage = bookInfo.coverImage
			if params.isKindle && !info.ext.hasPrefix("jp") {
				if coverImage == nil { coverImage = coverImageBytes.flatMap(ImageUtils.decode) }
				info.ext = "jpeg"
			}
			info.rotateAngle = 0
			var p = imageWriteParams
			p.autoMarginLimitH = 0; p.autoMarginLimitV = 0; p.autoMarginWhiteLevel = 0; p.autoMarginPadding = 0; p.autoMarginNombre = 0; p.nombreSize = 0
			p.maxImagePixels = 0
			let data: Data?
			if let coverImage {
				p.maxImageW = 0; p.maxImageH = 0
				data = ImageUtils.writeImage(nil, coverImage, info, p, log: log)
				bookInfo.coverImage = nil
			} else {
				p.maxImageW = params.coverW; p.maxImageH = params.coverH
				data = ImageUtils.writeImage(coverImageBytes, nil, info, p, log: log)
			}
			if let data, let name = info.outFileName {
				try addEntry(Self.opsPath + Self.imagesPath + name, data, compressed: false)
			} else {
				log.error("表紙画像取得エラー: " + (bookInfo.coverFileName ?? ""))
			}
			imageInfos.removeFirst()
			addProgress(10)
		}
		if canceled { return }

		// body images (image-only books were written in writeSections)
		if srcExt == "txt" {
			for name in imageInfoReader.imageFileNames {
				guard let srcImageFileName = imageInfoReader.correctExt(name) else { addProgress(10); continue }
				if outImageFileNames.contains(srcImageFileName) {
					if let info = imageInfoReader.imageInfo(srcImageFileName) {
						let file = imageInfoReader.imageFile(srcImageFileName)
						if let data = try? Data(contentsOf: file), let name = info.outFileName {
							if let out = ImageUtils.writeImage(data, nil, info, imageWriteParams, log: log) {
								try addEntry(Self.opsPath + Self.imagesPath + name, out, compressed: false)
							}
							outImageFileNames.remove(srcImageFileName)
						}
					} else {
						log.println("[WARN] 画像ファイルなし: " + srcImageFileName)
					}
				}
				if canceled { return }
				addProgress(10)
			}
		} else if !bookInfo.imageOnly {
			try ArchiveReader(url: srcFile).forEach { entry, read in
				guard !entry.isDirectory else { return true }
				let srcImageFileName = entry.name.jsub(archivePathLength)
				if outImageFileNames.contains(srcImageFileName) {
					try writeArchiveImage(srcImageFileName, read())
				}
				return !canceled
			}
		}
		progress?(progressTotal, progressTotal)
	}

	var imageWriteParams: ImageUtils.WriteParams {
		var p = ImageUtils.WriteParams()
		p.jpegQuality = params.jpegQuality
		p.gamma = ImageUtils.WriteParams.gammaTable(params.gamma)
		p.maxImagePixels = params.maxImagePixels
		p.maxImageW = params.maxImageW
		p.maxImageH = params.maxImageH
		p.dispW = params.dispW
		p.dispH = params.dispH
		p.autoMarginLimitH = params.autoMarginLimitH
		p.autoMarginLimitV = params.autoMarginLimitV
		p.autoMarginWhiteLevel = params.autoMarginWhiteLevel
		p.autoMarginPadding = params.autoMarginPadding
		p.autoMarginNombre = params.autoMarginNombre
		p.nombreSize = params.autoMarginNombreSize
		return p
	}

	/// TOC nesting: renumber levels from 0, then compute nav/ncx open/close counts.
	private func buildTocLevels() {
		var chapterCounts = [Int](repeating: 0, count: 10)
		for info in chapterInfos { chapterCounts[max(0, min(9, info.chapterLevel))] += 1 }
		var newLevel = [Int](repeating: 0, count: 10)
		var level = 0
		for i in 0..<chapterCounts.count where chapterCounts[i] > 0 { newLevel[i] = level; level += 1 }
		for info in chapterInfos { info.chapterLevel = newLevel[max(0, min(9, info.chapterLevel))] }

		var pre = ChapterInfo(nil, nil, nil, 0)
		for info in chapterInfos {
			info.levelStart = max(0, info.chapterLevel - pre.chapterLevel)
			pre.levelEnd = max(0, pre.chapterLevel - info.chapterLevel)
			pre = info
		}
		if let last = chapterInfos.last { last.levelEnd = last.chapterLevel }

		var ncxDepth = 1
		if params.ncxNest {
			var minLevel = 99, maxLevel = 0
			var navPointLevel = [Int](repeating: 0, count: 10)
			var prev: ChapterInfo? = nil
			for info in chapterInfos {
				if let p = prev {
					let preLevel = p.chapterLevel, curLevel = info.chapterLevel
					minLevel = min(minLevel, curLevel)
					maxLevel = max(maxLevel, curLevel)
					navPointLevel[preLevel] = 1
					if preLevel < curLevel {
						p.navClose = 0
					} else if preLevel > curLevel {
						var close = 0
						for i in curLevel..<navPointLevel.count where navPointLevel[i] == 1 { close += 1; navPointLevel[i] = 0 }
						p.navClose = close
					} else {
						p.navClose = 1
						navPointLevel[preLevel] = 0
					}
				}
				prev = info
			}
			if minLevel < maxLevel { ncxDepth = maxLevel - minLevel + 1 }
			if let last = chapterInfos.last {
				last.navClose = 1 + navPointLevel.filter { $0 == 1 }.count
			}
		}
		velocityContext.put("ncx_depth", ncxDepth)
	}

	/// Writes an archive image that the text referenced, rotating to fit the screen if configured.
	func writeArchiveImage(_ name: String, _ data: Data) throws {
		guard let srcImageFileName = imageInfoReader.correctExt(name), let info = imageInfoReader.imageInfo(srcImageFileName) else { return }
		if info.id != nil, let outName = info.outFileName {
			let dW = Double(params.dispW), dH = Double(params.dispH)
			if Double(info.width) / Double(info.height) >= dW / dH {
				if params.rotateAngle != 0 && params.dispW < params.dispH && Double(info.height) / Double(info.width) < dW / dH { info.rotateAngle = params.rotateAngle }
			} else if params.rotateAngle != 0 && params.dispW > params.dispH && Double(info.height) / Double(info.width) > dW / dH {
				info.rotateAngle = params.rotateAngle
			}
			if let out = ImageUtils.writeImage(data, nil, info, imageWriteParams, log: log) {
				try addEntry(Self.opsPath + Self.imagesPath + outName, out, compressed: false)
			}
		}
		addProgress(10)
	}

	// MARK: Sections

	func writeSections(_ converter: AozoraConverter, _ lines: [String]?, _ srcFile: URL, _ srcExt: String) throws {
		converter.vertical = bookInfo.vertical
		converter.convertTextToEpub3(self, lines ?? [], bookInfo)
		try endSection()
	}

	/// Appends text to the open section (the converter's `out.write`).
	func write(_ s: String) { sectionBuffer += s }

	/// Closes the current section and opens the next one.
	func nextSection(_ lineNum: Int, _ pageType: Int, _ imagePageType: Int, _ srcImageFilePath: String?) {
		if sectionIndex > 0 { try? endSection() }
		startSection(lineNum, pageType, imagePageType, srcImageFilePath)
	}

	func startSection(_ lineNum: Int, _ pageType: Int, _ imagePageType: Int, _ srcImageFilePath: String?) {
		sectionIndex += 1
		let sectionId = Self.format4(sectionIndex)
		let sectionInfo = SectionInfo(sectionId)
		switch imagePageType {
		case PageBreakType.imagePageW: sectionInfo.imagePage = true; sectionInfo.imageFitW = true
		case PageBreakType.imagePageH: sectionInfo.imagePage = true; sectionInfo.imageFitH = true
		case PageBreakType.imagePageNoFit: sectionInfo.imagePage = true
		default: break
		}
		if pageType == PageBreakType.pageMiddle { sectionInfo.isMiddle = true }
		else if pageType == PageBreakType.pageBottom { sectionInfo.isBottom = true }
		sectionInfos.append(sectionInfo)
		beginSection(sectionId, sectionInfo, template: Self.opsPath + Self.xhtmlPath + "xhtml_header.vm")
	}

	/// Opens xhtml/<id>.xhtml and renders its header template.
	func beginSection(_ sectionId: String, _ sectionInfo: SectionInfo, template: String) {
		currentSectionPath = Self.opsPath + Self.xhtmlPath + sectionId + ".xhtml"
		velocityContext.put("sectionInfo", sectionInfo)
		do {
			sectionBuffer = try merge(template)
		} catch {
			log.error("テンプレートエラー: \(template): \(error)")
			sectionBuffer = ""
		}
	}

	/// Closes the open section as-is (for templates that are complete pages).
	func finishSectionWithoutFooter() throws {
		guard let path = currentSectionPath else { return }
		try addEntry(path, sectionBuffer)
		sectionBuffer = ""
		currentSectionPath = nil
	}

	func endSection() throws {
		guard let path = currentSectionPath else { return }
		sectionBuffer += try merge(Self.opsPath + Self.xhtmlPath + "xhtml_footer.vm")
		try addEntry(path, sectionBuffer)
		sectionBuffer = ""
		currentSectionPath = nil
	}

	func addChapter(_ chapterId: String?, _ name: String?, _ chapterLevel: Int) {
		guard let sectionInfo = sectionInfos.last else { return }
		chapterInfos.append(ChapterInfo(sectionInfo.sectionId, chapterId, name, chapterLevel))
	}

	func addGaijiFont(_ className: String, _ file: URL) {
		if gaijiNameSet.contains(className) { return }
		vecGaijiInfo.append(GaijiInfo(className, file))
		gaijiNameSet.insert(className)
	}

	// MARK: Images

	/// Renamed path (../images/0001.jpg) for an image; nil if it isn't output here.
	func getImageFilePath(_ srcImageFileNameIn: String, _ lineNum: Int) -> String? {
		var srcImageFileName = srcImageFileNameIn
		var isCover = false
		var imageInfo = imageInfoReader.imageInfo(srcImageFileName)
		if imageInfo == nil, let alt = imageInfoReader.correctExt(srcImageFileName) {
			imageInfo = imageInfoReader.imageInfo(alt)
			if imageInfo != nil {
				log.warn(lineNum, "画像拡張子変更", srcImageFileName)
				srcImageFileName = alt
			}
		}
		imageIndex += 1 // count even missing files so numbering follows the text
		guard let info = imageInfo else {
			log.warn(lineNum, "画像ファイルなし", srcImageFileName)
			return nil
		}
		var imageId = info.id
		if imageId == nil {
			imageId = Self.format4(imageIndex)
			imageInfos.append(info)
			outImageFileNames.insert(srcImageFileName)
			if imageIndex - 1 == bookInfo.coverImageIndex { isCover = true }
		}
		let outImageFileName = imageId! + "." + info.ext.replaceFirst("jpeg", "jpg")
		info.id = imageId
		info.outFileName = outImageFileName
		if bookInfo.insertCoverPage && isCover { return nil }
		return "../" + Self.imagesPath + outImageFileName
	}

	var isCoverImage: Bool { imageIndex == bookInfo.coverImageIndex }

	/// Whether an image should get its own page, float, or fit inline.
	func getImagePageType(_ srcFilePath: String?, _ tagLevel: Int, _ lineNum: Int, _ hasCaption: Bool) -> Int {
		guard let srcFilePath else { return PageBreakType.imagePageNone }
		var info = imageInfoReader.imageInfo(srcFilePath)
		if info == nil, let alt = imageInfoReader.correctExt(srcFilePath) { info = imageInfoReader.imageInfo(alt) }
		guard let imageInfo = info else { return PageBreakType.imagePageNone }

		let imageOrgWidth = Float(imageInfo.width)
		let imageOrgHeight = Float(imageInfo.height)
		var imageWidth = imageOrgWidth
		var imageHeight = imageOrgHeight
		if params.imageScale > 0 {
			imageWidth *= params.imageScale
			imageHeight *= params.imageScale
		}
		let dispW = Float(params.dispW), dispH = Float(params.dispH)
		let dRatio = Double(params.dispW) / Double(params.dispH)

		if params.imageFloatType != 0 && (imageOrgWidth >= 64 || imageOrgHeight >= 64) &&
			imageOrgWidth <= Float(params.imageFloatW) && imageOrgHeight <= Float(params.imageFloatH) {
			if params.imageFloatType == 1 { return imageWidth > dispW ? PageBreakType.imageInlineTopW : PageBreakType.imageInlineTop }
			return imageWidth > dispW ? PageBreakType.imageInlineBottomW : PageBreakType.imageInlineBottom
		}
		if imageOrgWidth >= Float(params.singlePageWidth) || imageOrgWidth >= Float(params.singlePageSizeW) && imageOrgHeight >= Float(params.singlePageSizeH) {
			if tagLevel == 0 {
				if !hasCaption {
					if imageWidth <= dispW && imageHeight < dispH {
						if !params.fitImage { return PageBreakType.imagePageNoFit }
					} else if params.imageSizeType == SectionInfo.imageSizeTypeAuto {
						return PageBreakType.imagePageNoFit
					}
					if Double(imageWidth / imageHeight) > dRatio {
						if params.rotateAngle != 0 && params.dispW < params.dispH && imageWidth > imageHeight * 1.1 {
							imageInfo.rotateAngle = params.rotateAngle
							return Double(imageHeight / imageWidth) > dRatio ? PageBreakType.imagePageW : PageBreakType.imagePageH
						}
						return PageBreakType.imagePageW
					} else {
						if params.rotateAngle != 0 && params.dispW > params.dispH && imageWidth * 1.1 < imageHeight {
							imageInfo.rotateAngle = params.rotateAngle
							return Double(imageHeight / imageWidth) > dRatio ? PageBreakType.imagePageW : PageBreakType.imagePageH
						}
						return PageBreakType.imagePageH
					}
				} else {
					log.warn(lineNum, "キャプションがあるため画像単ページ化されません")
				}
			} else {
				log.warn(lineNum, "タグ内のため画像単ページ化できません")
			}
		}
		if imageWidth > dispW {
			return Double(imageWidth / imageHeight) > dRatio ? PageBreakType.imageInlineW : PageBreakType.imageInlineH
		}
		if imageHeight > dispH { return PageBreakType.imageInlineH }
		return PageBreakType.imagePageNone
	}

	/// Display width in % of the screen; 0 at scale 1, -1 for small (gaiji-sized) images.
	func getImageWidthRatio(_ srcFilePath: String, _ hasCaption: Bool) -> Double {
		if params.imageScale == 0 { return 0 }
		var ratio = 0.0
		if let info = imageInfoReader.imageInfo(srcFilePath) {
			if bookInfo.vertical { if info.width <= 64 { return -1 } }
			else if info.height <= 64 { return -1 }
			var imgW = info.width, imgH = info.height
			if info.rotateAngle == 90 || info.rotateAngle == 270 { imgW = info.height; imgH = info.width }
			var wRatio = Double(imgW) / Double(params.dispW) * Double(params.imageScale) * 100
			let hRatio = Double(imgH) / Double(params.dispH) * Double(params.imageScale) * 100
			if hasCaption {
				if hRatio >= 90 { wRatio *= 100 / hRatio; wRatio *= 0.9 }
			} else if hRatio >= 100 {
				wRatio *= 100 / hRatio
			}
			ratio = wRatio
		}
		return min(100, ratio)
	}

	// MARK: Helpers

	static func format4(_ n: Int) -> String { String(format: "%04d", n) }

	/// "2011-06-29T12:00:00Z" in UTC (the Java app wrote local time with a Z suffix).
	static let modifiedFormat: DateFormatter = {
		let f = DateFormatter()
		f.locale = Locale(identifier: "en_US_POSIX")
		f.timeZone = TimeZone(identifier: "UTC")
		f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
		return f
	}()

	/// Java `UUID.nameUUIDFromBytes` (MD5, version 3).
	static func nameUUID(_ name: String) -> String {
		var bytes = Array(Insecure.MD5.hash(data: Data(name.utf8)))
		bytes[6] = (bytes[6] & 0x0F) | 0x30
		bytes[8] = (bytes[8] & 0x3F) | 0x80
		let hex = bytes.map { String(format: "%02x", $0) }.joined()
		let h = Array(hex)
		return String(h[0..<8]) + "-" + String(h[8..<12]) + "-" + String(h[12..<16]) + "-" + String(h[16..<20]) + "-" + String(h[20..<32])
	}
}
