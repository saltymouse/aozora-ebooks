import Foundation

/// Every conversion option of AozoraEpub3, with the Java GUI's defaults.
///
/// Settings round-trip through the Java `.ini` (java.util.Properties) keys, so the
/// bundled device presets and a user's old AozoraEpub3.ini/profile files still load.
public struct ConversionSettings: Codable, Equatable, Sendable {
	// MARK: Title & cover
	public var titleType: TitleType = .titleAuthor
	/// First line is the publisher.
	public var pubFirst = false
	/// Prefer "[作者] 題名" from the file name over the text.
	public var useFileName = false
	public enum CoverSource: Codable, Equatable, Sendable {
		case firstIllustration
		case sameNameImage
		case none
		case file(String)
	}
	public var cover: CoverSource = .firstIllustration
	/// Reuse the cover chosen last time for the same file.
	public var coverHistory = true
	/// Only use an illustration as cover if it appears within this many lines (0 = no limit).
	public var maxCoverLine = 10

	// MARK: Pages
	public var coverPage = true
	public var titlePageWrite = true
	public var titlePage: TitlePageType = .middle
	public var tocPage = false
	public var tocVertical = true

	// MARK: Output
	public var ext = ".epub"
	public var autoFileName = true
	public var overWrite = true
	public var samePath = true
	public var dstPath = ""
	public var encoding: TextEncoding = .shiftJIS
	public var vertical = true
	public var confirm = true
	/// Confirm sheet: keep the original image when the cover is cropped.
	public var replaceCover = false

	// MARK: Images
	public var noIllust = false
	public var dispW = 600
	public var dispH = 800
	public var coverW = 600
	public var coverH = 800
	public var imageScaleChecked = true
	public var imageScale: Float = 1.0
	public var imageFloat = false
	/// 0 = top/left, 1 = bottom/right
	public var imageFloatType = 0
	public var imageFloatW = 600
	public var imageFloatH = 400
	public var singlePageSizeW = 400
	public var singlePageSizeH = 600
	public var singlePageWidth = 600
	/// 1 = no size (device scales), 3 = fit to screen aspect
	public var imageSizeType = 3
	public var fitImage = true
	public var svgImage = false
	/// 0 = none, 1 = right, 2 = left
	public var rotateImage = 0
	public var imageFloatPage = false
	public var imageFloatBlock = false
	public var jpegQuality = 85
	public var gamma = false
	public var gammaValue: Float = 1.0
	public var resizeW = false
	public var resizeNumW = 2048
	public var resizeH = false
	public var resizeNumH = 2048
	public var autoMargin = false
	public var autoMarginLimitH = 15
	public var autoMarginLimitV = 15
	public var autoMarginWhiteLevel = 80
	public var autoMarginPadding: Float = 1.0
	/// 0 = none, 1 = top, 2 = bottom, 3 = both
	public var autoMarginNombre = 0
	public var autoMarginNombreSize: Float = 3.0

	// MARK: Text
	/// 0 = as is, 1 = hide at line end (Kobo/Kindle), 2 = push out (Reader)
	public var spaceHyphenation = 0
	/// ［＃「○○」に「××」の注記］: 0 = hidden, 1 = ruby, 2 = small text
	public var chukiRuby = 0
	public var autoYoko = true
	public var autoYokoNum1 = false
	public var autoYokoNum3 = false
	public var autoYokoEQ1 = false
	public var commentPrint = false
	public var commentConvert = false
	public var markId = false
	public var removeEmptyLine = 0
	public var maxEmptyLine = 0
	public var forceIndent = false
	public var pageBreak = true
	/// KB
	public var pageBreakSize = 400
	public var pageBreakEmpty = false
	public var pageBreakEmptyLine = 2
	public var pageBreakEmptySize = 300
	public var pageBreakChapter = false
	public var pageBreakChapterSize = 200

	// MARK: Table of contents
	public var maxChapterNameLength = 64
	public var coverPageToc = false
	public var titleToc = true
	public var chapterUseNextLine = false
	public var chapterExclude = true
	public var navNest = false
	public var ncxNest = false
	public var chapterSection = true
	public var chapterH = true
	public var chapterH1 = true
	public var chapterH2 = true
	public var chapterH3 = true
	public var sameLineChapter = false
	public var chapterName = true
	public var chapterNumOnly = false
	public var chapterNumTitle = false
	public var chapterNumParen = false
	public var chapterNumParenTitle = false
	public var chapterPattern = false
	public var chapterPatternText = "^(見出し１|見出し２|見出し３)$"
	public static let chapterPatternExamples = [
		"^(見出し１|見出し２|見出し３)$",
		"^(†|【|●|▼|■)",
		"^(0-9|０-９|一|二|三|四|五|六|七|八|九|十|〇)",
		"^[1|2|１|２]?[0-9|０-９]月[1-3|１-３]?[0-9|０-９]日",
		"^(一|十)?(一|二|三|四|五|六|七|八|九|十|〇)月(一|十|二十?|三十?)?(一|二|三|四|五|六|七|八|九|十|〇)日",
	]

	// MARK: Style
	public var pageMargin: [String] = ["0.5", "0.5", "0.5", "0.5"]
	/// 0 = em (字), 1 = %
	public var pageMarginUnit = 0
	public var bodyMargin: [String] = ["0", "0", "0", "0"]
	public var bodyMarginUnit = 0
	public var lineHeight: Float = 1.8
	public var fontSize = 100
	public var boldUseGothic = false
	public var gothicUseBold = false

	// MARK: Characters
	/// 0 = as is, 1 = overlay, 2 = font
	public var dakutenType = 1
	public var ivsBMP = false
	public var ivsSSP = false

	// MARK: Web
	public var webInterval: Float = 0.5
	public var cachePath = ""
	public var webModifiedExpire: Float = 24
	public var webConvertUpdated = false
	public var webModifiedOnly = false
	public var webModifiedTail = false
	public var webBeforeChapter = false
	public var webBeforeChapterCount = 1
	public var userAgent = ""

	public init() {}
}

// MARK: - .ini compatibility

extension ConversionSettings {
	/// Applies Java .ini keys on top of the current values; missing keys leave values unchanged,
	/// like the Java GUI's loadProperties.
	public mutating func apply(ini p: [String: String]) {
		func bool(_ k: String, _ v: inout Bool) { if let s = p[k] { v = s == "1" } }
		func int(_ k: String, _ v: inout Int) { if let s = p[k], let i = Int(s.trimmingCharacters(in: .whitespaces)) { v = i } }
		func float(_ k: String, _ v: inout Float) { if let s = p[k], let f = Float(s.trimmingCharacters(in: .whitespaces)) { v = f } }
		func str(_ k: String, _ v: inout String) { if let s = p[k] { v = s } }

		if let s = p["TitleType"], let i = Int(s), let t = TitleType(rawValue: i) { titleType = t }
		bool("PubFirst", &pubFirst)
		bool("UseFileName", &useFileName)
		if p.keys.contains("Cover") {
			let c = p["Cover"] ?? ""
			if c.isEmpty { cover = .firstIllustration }
			else if c == "[入力ファイル名と同じ画像(png,jpg)]" { cover = .sameNameImage }
			else if c == "[表紙無し]" { cover = .none }
			else if c == "[先頭の挿絵]" { cover = .firstIllustration }
			else { cover = .file(c) }
		}
		bool("CoverHistory", &coverHistory)
		int("MaxCoverLine", &maxCoverLine)
		bool("CoverPage", &coverPage)
		bool("TitlePageWrite", &titlePageWrite)
		if let s = p["TitlePage"], let i = Int(s), let t = TitlePageType(rawValue: i) { titlePage = t }
		bool("TocPage", &tocPage)
		bool("TocVertical", &tocVertical)
		if let s = p["Ext"], !s.isEmpty { ext = s }
		bool("AutoFileName", &autoFileName)
		bool("OverWrite", &overWrite)
		bool("SamePath", &samePath)
		str("DstPath", &dstPath)
		bool("MarkId", &markId)
		bool("Vertical", &vertical)
		if let s = p["EncType"] { encoding = s == "1" || s == "UTF-8" ? .utf8 : .shiftJIS }
		bool("ChkConfirm", &confirm)
		bool("ReplaceCover", &replaceCover)

		bool("NoIllust", &noIllust)
		int("DispW", &dispW); int("DispH", &dispH)
		int("CoverW", &coverW); int("CoverH", &coverH)
		int("SinglePageSizeW", &singlePageSizeW); int("SinglePageSizeH", &singlePageSizeH); int("SinglePageWidth", &singlePageWidth)
		if let s = p["ImageSizeType"], let i = Int(s) { imageSizeType = i == 1 ? 1 : 3 }
		bool("FitImage", &fitImage)
		bool("SvgImage", &svgImage)
		int("RotateImage", &rotateImage)
		imageScaleChecked = p["ImageScaleChecked"] == "1"
		float("ImageScale", &imageScale)
		bool("ImageFloat", &imageFloat)
		int("ImageFloatW", &imageFloatW); int("ImageFloatH", &imageFloatH)
		int("ImageFloatType", &imageFloatType)
		bool("ResizeW", &resizeW); int("ResizeNumW", &resizeNumW)
		bool("ResizeH", &resizeH); int("ResizeNumH", &resizeNumH)
		imageFloatPage = p["ImageFloatPage"] == "1"
		imageFloatBlock = p["ImageFloatBlock"] == "1"
		int("JpegQuality", &jpegQuality)
		bool("Gamma", &gamma); float("GammaValue", &gammaValue)
		bool("AutoMargin", &autoMargin)
		int("AutoMarginLimitH", &autoMarginLimitH); int("AutoMarginLimitV", &autoMarginLimitV)
		int("AutoMarginWhiteLevel", &autoMarginWhiteLevel)
		float("AutoMarginPadding", &autoMarginPadding)
		int("AutoMarginNombre", &autoMarginNombre)
		float("AutoMarginNombreSize", &autoMarginNombreSize)

		int("SpaceHyphenation", &spaceHyphenation)
		int("ChukiRuby", &chukiRuby)
		bool("AutoYoko", &autoYoko); bool("AutoYokoNum1", &autoYokoNum1); bool("AutoYokoNum3", &autoYokoNum3); bool("AutoYokoEQ1", &autoYokoEQ1)
		bool("CommentPrint", &commentPrint); bool("CommentConvert", &commentConvert)
		int("RemoveEmptyLine", &removeEmptyLine)
		int("MaxEmptyLine", &maxEmptyLine)
		bool("ForceIndent", &forceIndent)
		bool("PageBreak", &pageBreak); int("PageBreakSize", &pageBreakSize)
		bool("PageBreakEmpty", &pageBreakEmpty); int("PageBreakEmptyLine", &pageBreakEmptyLine); int("PageBreakEmptySize", &pageBreakEmptySize)
		bool("PageBreakChapter", &pageBreakChapter); int("PageBreakChapterSize", &pageBreakChapterSize)

		int("MaxChapterNameLength", &maxChapterNameLength)
		bool("CoverPageToc", &coverPageToc); bool("TitleToc", &titleToc)
		bool("ChapterUseNextLine", &chapterUseNextLine); bool("ChapterExclude", &chapterExclude)
		bool("NavNest", &navNest); bool("NcxNest", &ncxNest)
		bool("ChapterSection", &chapterSection)
		bool("ChapterH", &chapterH); bool("ChapterH1", &chapterH1); bool("ChapterH2", &chapterH2); bool("ChapterH3", &chapterH3)
		bool("SameLineChapter", &sameLineChapter)
		bool("ChapterName", &chapterName)
		bool("ChapterNumOnly", &chapterNumOnly); bool("ChapterNumTitle", &chapterNumTitle)
		bool("ChapterNumParen", &chapterNumParen); bool("ChapterNumParenTitle", &chapterNumParenTitle)
		bool("ChapterPattern", &chapterPattern); str("ChapterPatternText", &chapterPatternText)

		if let s = p["PageMargin"] { let v = s.components(separatedBy: ","); if v.count == 4 { pageMargin = v } }
		int("PageMarginUnit", &pageMarginUnit)
		if let s = p["BodyMargin"] { let v = s.components(separatedBy: ","); if v.count == 4 { bodyMargin = v } }
		int("BodyMarginUnit", &bodyMarginUnit)
		if let s = p["LineHeight"], let f = Float(s) { lineHeight = f }
		if let s = p["FontSize"], let f = Float(s) { fontSize = Int(f) }
		bool("BoldUseGothic", &boldUseGothic); bool("GothicUseBold", &gothicUseBold)
		int("DakutenType", &dakutenType)
		bool("IvsBMP", &ivsBMP); bool("IvsSSP", &ivsSSP)

		float("WebInterval", &webInterval)
		str("CachePath", &cachePath)
		if cachePath == ".cache" { cachePath = "" }
		float("WebModifiedExpire", &webModifiedExpire)
		bool("WebConvertUpdated", &webConvertUpdated); bool("WebModifiedOnly", &webModifiedOnly); bool("WebModifiedTail", &webModifiedTail)
		bool("WebBeforeChapter", &webBeforeChapter); int("WebBeforeChapterCount", &webBeforeChapterCount)
		str("UserAgent", &userAgent)
	}

	/// Settings as Java .ini keys (what the Java GUI's setProperties wrote).
	public var ini: [String: String] {
		func b(_ v: Bool) -> String { v ? "1" : "" }
		var p: [String: String] = [:]
		p["TitleType"] = String(titleType.rawValue)
		p["PubFirst"] = b(pubFirst)
		p["UseFileName"] = b(useFileName)
		p["AutoFileName"] = b(autoFileName)
		p["MarkId"] = b(markId)
		p["Vertical"] = b(vertical)
		p["Ext"] = ext
		p["ChkConfirm"] = b(confirm)
		switch cover {
		case .firstIllustration: p["Cover"] = ""
		case .sameNameImage: p["Cover"] = "[入力ファイル名と同じ画像(png,jpg)]"
		case .none: p["Cover"] = "[表紙無し]"
		case .file(let f): p["Cover"] = f
		}
		p["CoverHistory"] = b(coverHistory)
		p["MaxCoverLine"] = String(maxCoverLine)
		p["CoverPage"] = b(coverPage)
		p["TitlePageWrite"] = b(titlePageWrite)
		p["TitlePage"] = String(titlePage.rawValue)
		p["TocPage"] = b(tocPage)
		p["TocVertical"] = b(tocVertical)
		p["NoIllust"] = b(noIllust)
		p["DispW"] = String(dispW); p["DispH"] = String(dispH)
		p["CoverW"] = String(coverW); p["CoverH"] = String(coverH)
		p["ImageScaleChecked"] = b(imageScaleChecked)
		p["ImageScale"] = javaString(imageScale)
		p["ImageFloat"] = b(imageFloat)
		p["ImageFloatType"] = String(imageFloatType)
		p["ImageFloatW"] = String(imageFloatW); p["ImageFloatH"] = String(imageFloatH)
		p["ResizeW"] = b(resizeW); p["ResizeH"] = b(resizeH)
		p["ResizeNumW"] = String(resizeNumW); p["ResizeNumH"] = String(resizeNumH)
		p["SinglePageSizeW"] = String(singlePageSizeW); p["SinglePageSizeH"] = String(singlePageSizeH); p["SinglePageWidth"] = String(singlePageWidth)
		p["ImageSizeType"] = String(imageSizeType)
		p["FitImage"] = b(fitImage)
		p["SvgImage"] = b(svgImage)
		p["RotateImage"] = String(rotateImage)
		p["ImageFloatPage"] = b(imageFloatPage)
		p["ImageFloatBlock"] = b(imageFloatBlock)
		p["JpegQuality"] = String(jpegQuality)
		p["Gamma"] = b(gamma)
		p["GammaValue"] = javaString(gammaValue)
		p["AutoMargin"] = b(autoMargin)
		p["AutoMarginLimitH"] = String(autoMarginLimitH); p["AutoMarginLimitV"] = String(autoMarginLimitV)
		p["AutoMarginWhiteLevel"] = String(autoMarginWhiteLevel)
		p["AutoMarginPadding"] = javaString(autoMarginPadding)
		p["AutoMarginNombre"] = String(autoMarginNombre)
		p["AutoMarginNombreSize"] = javaString(autoMarginNombreSize)
		p["SpaceHyphenation"] = String(spaceHyphenation)
		p["ChukiRuby"] = String(chukiRuby)
		p["AutoYoko"] = b(autoYoko); p["AutoYokoNum1"] = b(autoYokoNum1); p["AutoYokoNum3"] = b(autoYokoNum3); p["AutoYokoEQ1"] = b(autoYokoEQ1)
		p["CommentPrint"] = b(commentPrint); p["CommentConvert"] = b(commentConvert)
		p["RemoveEmptyLine"] = String(removeEmptyLine)
		p["MaxEmptyLine"] = String(maxEmptyLine)
		p["ForceIndent"] = b(forceIndent)
		p["PageBreak"] = b(pageBreak); p["PageBreakSize"] = String(pageBreakSize)
		p["PageBreakEmpty"] = b(pageBreakEmpty); p["PageBreakEmptyLine"] = String(pageBreakEmptyLine); p["PageBreakEmptySize"] = String(pageBreakEmptySize)
		p["PageBreakChapter"] = b(pageBreakChapter); p["PageBreakChapterSize"] = String(pageBreakChapterSize)
		p["MaxChapterNameLength"] = String(maxChapterNameLength)
		p["CoverPageToc"] = b(coverPageToc); p["TitleToc"] = b(titleToc)
		p["ChapterUseNextLine"] = b(chapterUseNextLine); p["ChapterExclude"] = b(chapterExclude)
		p["NavNest"] = b(navNest); p["NcxNest"] = b(ncxNest)
		p["ChapterSection"] = b(chapterSection)
		p["ChapterH"] = b(chapterH); p["ChapterH1"] = b(chapterH1); p["ChapterH2"] = b(chapterH2); p["ChapterH3"] = b(chapterH3)
		p["SameLineChapter"] = b(sameLineChapter)
		p["ChapterName"] = b(chapterName)
		p["ChapterNumOnly"] = b(chapterNumOnly); p["ChapterNumTitle"] = b(chapterNumTitle)
		p["ChapterNumParen"] = b(chapterNumParen); p["ChapterNumParenTitle"] = b(chapterNumParenTitle)
		p["ChapterPattern"] = b(chapterPattern); p["ChapterPatternText"] = chapterPatternText
		p["PageMargin"] = pageMargin.joined(separator: ",")
		p["PageMarginUnit"] = String(pageMarginUnit)
		p["BodyMargin"] = bodyMargin.joined(separator: ",")
		p["BodyMarginUnit"] = String(bodyMarginUnit)
		p["LineHeight"] = javaString(lineHeight)
		p["FontSize"] = String(fontSize)
		p["BoldUseGothic"] = b(boldUseGothic); p["GothicUseBold"] = b(gothicUseBold)
		p["DakutenType"] = String(dakutenType)
		p["IvsBMP"] = b(ivsBMP); p["IvsSSP"] = b(ivsSSP)
		p["WebInterval"] = javaString(webInterval)
		p["CachePath"] = cachePath
		p["WebModifiedExpire"] = javaString(webModifiedExpire)
		p["WebConvertUpdated"] = b(webConvertUpdated); p["WebModifiedOnly"] = b(webModifiedOnly); p["WebModifiedTail"] = b(webModifiedTail)
		p["WebBeforeChapter"] = b(webBeforeChapter); p["WebBeforeChapterCount"] = String(webBeforeChapterCount)
		p["ReplaceCover"] = b(replaceCover)
		p["EncType"] = encoding == .utf8 ? "1" : "0"
		p["OverWrite"] = b(overWrite)
		p["SamePath"] = b(samePath)
		p["DstPath"] = dstPath
		if !userAgent.isEmpty { p["UserAgent"] = userAgent }
		return p
	}
}

/// java.util.Properties text format (ISO-8859-1 with \uXXXX escapes, # and ! comments).
public enum JavaProperties {
	public static func parse(_ data: Data) -> [String: String] {
		// Properties files are Latin-1 with \u escapes; tolerate UTF-8 presets too.
		let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
		var result: [String: String] = [:]
		var logical = ""
		for raw in TextIO.lines(text) {
			var line = logical.isEmpty ? raw.trimmingCharacters(in: .whitespaces) : raw.drop(while: { $0 == " " || $0 == "\t" }).description
			if logical.isEmpty && (line.isEmpty || line.hasPrefix("#") || line.hasPrefix("!")) { continue }
			// odd number of trailing backslashes continues the line
			let trailing = line.reversed().prefix(while: { $0 == "\\" }).count
			if trailing % 2 == 1 {
				line.removeLast()
				logical += line
				continue
			}
			logical += line
			let (k, v) = splitKeyValue(logical)
			result[unescape(k)] = unescape(v)
			logical = ""
		}
		return result
	}

	private static func splitKeyValue(_ line: String) -> (String, String) {
		var key = ""
		var it = line.makeIterator()
		var escaped = false
		var rest = ""
		var found = false
		while let c = it.next() {
			if escaped { key.append("\\"); key.append(c); escaped = false; continue }
			if c == "\\" { escaped = true; continue }
			if c == "=" || c == ":" || c == " " || c == "\t" { found = true; break }
			key.append(c)
		}
		if found {
			while let c = it.next() { rest.append(c) }
			rest = String(rest.drop(while: { $0 == " " || $0 == "\t" }))
			if rest.hasPrefix("=") || rest.hasPrefix(":") { rest = String(rest.dropFirst().drop(while: { $0 == " " || $0 == "\t" })) }
		}
		return (key, rest)
	}

	private static func unescape(_ s: String) -> String {
		var out = ""
		var chars = Array(s.utf16)
		var i = 0
		var units: [UInt16] = []
		while i < chars.count {
			let c = chars[i]
			if c == 0x5C, i + 1 < chars.count {
				let n = chars[i + 1]
				switch n {
				case 0x75 where i + 5 < chars.count: // \uXXXX
					if let v = UInt16(String(decoding: chars[(i + 2)...(i + 5)], as: UTF16.self), radix: 16) { units.append(v); i += 6; continue }
				case 0x74: units.append(0x09); i += 2; continue
				case 0x6E: units.append(0x0A); i += 2; continue
				case 0x72: units.append(0x0D); i += 2; continue
				case 0x66: units.append(0x0C); i += 2; continue
				default: units.append(n); i += 2; continue
				}
			}
			units.append(c)
			i += 1
		}
		chars = units
		out = String(decoding: chars, as: UTF16.self)
		return out
	}

	/// Writes Properties text with non-ASCII escaped, as Java's store() does.
	public static func serialize(_ p: [String: String], comment: String? = nil) -> String {
		func esc(_ s: String, key: Bool) -> String {
			var out = ""
			for (i, u) in s.utf16.enumerated() {
				switch u {
				case 0x5C: out += "\\\\"
				case 0x09: out += "\\t"
				case 0x0A: out += "\\n"
				case 0x0D: out += "\\r"
				case 0x3D, 0x3A, 0x23, 0x21: out += "\\" + String(UnicodeScalar(UInt8(u)))
				case 0x20 where key || i == 0: out += "\\ "
				case 0x20...0x7E: out += String(UnicodeScalar(UInt8(u)))
				default: out += String(format: "\\u%04X", u)
				}
			}
			return out
		}
		var lines: [String] = []
		if let comment { lines.append("#" + comment) }
		for k in p.keys.sorted() { lines.append(esc(k, key: true) + "=" + esc(p[k]!, key: false)) }
		return lines.joined(separator: "\n") + "\n"
	}
}
