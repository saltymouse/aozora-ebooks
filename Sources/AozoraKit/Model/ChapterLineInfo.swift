import Foundation

/// A TOC candidate line found while pre-scanning the text (port of `ChapterLineInfo`).
public final class ChapterLineInfo {
	public enum Kind: Int, Sendable {
		case title = 1
		case pageBreak = 2
		case chukiH = 10, chukiH1 = 11, chukiH2 = 12, chukiH3 = 13
		case chapterName = 21
		case chapterNum = 22
		case pattern = 30
	}

	public static let levelTitle = 0
	public static let levelSection = 1
	public static let levelH1 = 1
	public static let levelH2 = 2
	public static let levelH3 = 3

	/// 0-based line number.
	public var lineNum: Int
	public var type: Kind
	/// TOC level; auto-detected headings add 10.
	public var level: Int
	/// The heading starts a new page (first text after a page break).
	public var pageBreakChapter: Bool
	/// The preceding line was empty.
	public var emptyNext: Bool
	public var chapterName: String?

	init(_ lineNum: Int, _ type: Kind, _ pageBreak: Bool, _ level: Int, _ emptyLineNext: Bool, _ chapterName: String? = nil) {
		self.lineNum = lineNum
		self.type = type
		self.pageBreakChapter = pageBreak
		self.level = level
		self.emptyNext = emptyLineNext
		self.chapterName = chapterName
	}

	/// The single-character label the Java confirm dialog showed.
	public var typeId: String {
		switch type {
		case .title: return "題"
		case .pageBreak: return ""
		case .chukiH: return "見"
		case .chukiH1: return "大"
		case .chukiH2: return "中"
		case .chukiH3: return "小"
		case .chapterName: return "章"
		case .chapterNum: return "数"
		case .pattern: return "他"
		}
	}

	static func getLevel(_ type: Kind) -> Int {
		switch type {
		case .title: return levelTitle
		case .pageBreak: return levelSection
		case .chukiH1: return levelH1
		case .chukiH2: return levelH2
		case .chukiH3: return levelH3
		case .chapterNum: return levelH2
		default: return levelH1
		}
	}

	/// Matched by a chapter-name, number or custom pattern rule.
	var isPattern: Bool {
		switch type {
		case .title, .pageBreak, .chukiH1, .chukiH2, .chukiH3: return false
		default: return true
		}
	}

	func joinChapterName(_ name: String) {
		if let chapterName { self.chapterName = chapterName + "　" + name } else { chapterName = name }
	}
}

/// A TOC entry as written to nav.xhtml / toc.ncx (port of `ChapterInfo`).
final class ChapterInfo: VelocityObject {
	var sectionId: String?
	var chapterId: String?
	var chapterName: String?
	var chapterLevel: Int
	var levelStart = 0
	var levelEnd = 0
	var navClose = 1

	init(_ sectionId: String?, _ chapterId: String?, _ chapterName: String?, _ chapterLevel: Int) {
		self.sectionId = sectionId
		self.chapterId = chapterId
		self.chapterName = chapterName
		self.chapterLevel = chapterLevel
	}

	var noTagChapterName: String? { chapterName.map(CharUtils.removeTag) }

	func vproperty(_ name: String) -> VValue {
		switch name {
		case "sectionid": return .from(sectionId)
		case "chapterid": return .from(chapterId)
		case "chaptername": return .from(chapterName)
		case "notagchaptername": return .from(noTagChapterName)
		case "chapterlevel": return .int(chapterLevel)
		// Velocity loops over int arrays of these sizes; Java returned null for 0.
		case "levelstart": return levelStart == 0 ? .null : .list(Array(repeating: .int(0), count: levelStart))
		case "levelend": return levelEnd == 0 ? .null : .list(Array(repeating: .int(0), count: levelEnd))
		case "navclose": return navClose <= 0 ? .null : .list(Array(repeating: .int(0), count: navClose))
		default: return .undefined
		}
	}
}

/// One xhtml file in the EPUB (port of `SectionInfo`).
final class SectionInfo: VelocityObject {
	static let imageSizeTypeAuto = 1
	static let imageSizeTypeHeight = 2
	static let imageSizeTypeAspect = 3

	var sectionId: String
	var imagePage = false
	var imageHeight: Double = -1
	var imageFitW = false
	var imageFitH = false
	var isMiddle = false
	var isBottom = false

	init(_ sectionId: String) { self.sectionId = sectionId }

	var imageHeightPercent: Double { Double(Int(imageHeight * 1000)) / 10.0 }

	func vproperty(_ name: String) -> VValue {
		switch name {
		case "sectionid": return .string(sectionId)
		case "imagepage": return .bool(imagePage)
		case "imageheight": return .double(imageHeight)
		case "imageheightpercent": return .double(imageHeightPercent)
		case "imageheightpadding": return .double(Double(Int((1 - imageHeight) * 1000)) / 20.0)
		case "imagefitw": return .bool(imageFitW)
		case "imagefith": return .bool(imageFitH)
		case "middle": return .bool(isMiddle)
		case "bottom": return .bool(isBottom)
		default: return .undefined
		}
	}
}

/// An external gaiji font embedded in the EPUB (port of `GaijiInfo`).
final class GaijiInfo: VelocityObject {
	let className: String
	let file: URL

	init(_ className: String, _ file: URL) {
		self.className = className
		self.file = file
	}

	func vproperty(_ name: String) -> VValue {
		switch name {
		case "classname": return .string(className)
		case "filename": return .string(file.lastPathComponent)
		default: return .undefined
		}
	}
}

/// Page break trigger (port of `PageBreakType`).
final class PageBreakType {
	static let imagePageNone = 0
	static let imagePageW = 1
	static let imagePageH = 2
	static let imagePageNoFit = 5
	static let imagePageAuto = 10
	static let imageInlineW = 11
	static let imageInlineH = 12
	static let imageInlineTop = 20
	static let imageInlineBottom = 21
	static let imageInlineTopW = 25
	static let imageInlineBottomW = 26

	static let pageNormal = 0
	static let pageMiddle = 1
	static let pageBottom = 2

	var ignoreEmptyPage: Bool
	var pageType: Int
	var imagePageType: Int
	var noChapter: Bool
	var srcFileName: String?
	var dstFileName: String?

	init(_ ignoreEmptyPage: Bool, _ pageType: Int, _ imagePageType: Int, _ noChapter: Bool = false) {
		self.ignoreEmptyPage = ignoreEmptyPage
		self.pageType = pageType
		self.imagePageType = imagePageType
		self.noChapter = noChapter
	}
}
