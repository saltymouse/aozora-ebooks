import Foundation
import CoreGraphics

/// How the title and author lines appear at the top of the text.
public enum TitleType: Int, CaseIterable, Codable, Sendable {
	case titleAuthor = 0, authorTitle, subtitleAuthor, titleOnly, titleAuthorOnly, none

	/// The labels the Java app used.
	public var japaneseName: String {
		["表題 → 著者名", "著者名 → 表題", "表題 → 著者名(副題優先)", "表題のみ(1行)", "表題+著者のみ(2行)", "なし"][rawValue]
	}

	var hasTitle: Bool { self != .none }
	var hasAuthor: Bool { self != .titleOnly && self != .none }
	var titleFirst: Bool {
		switch self {
		case .titleAuthor, .subtitleAuthor, .titleOnly, .titleAuthorOnly: return true
		default: return false
		}
	}
}

/// Title page placement (`BookInfo.TITLE_*`).
public enum TitlePageType: Int, Codable, Sendable {
	/// Title lines are not output.
	case none = -1
	/// Title stays in the body text.
	case normal = 0
	/// Separate centered title page.
	case middle = 1
	/// Separate horizontal title page.
	case horizontal = 2
}

/// Metadata and pre-scan results for one book (port of `BookInfo`).
public final class BookInfo: VelocityObject {
	public var titlePageType: TitlePageType = .normal

	var metaLines: [String?] = []
	var metaLineStart = 0
	public var totalLineNum = -1

	public var title: String?
	public var titleLine = -1
	public var titleAs: String?
	public var subTitle: String?
	public var subTitleLine = -1
	public var orgTitleLine = -1
	public var subOrgTitleLine = -1
	public var creator: String?
	public var creatorLine = -1
	public var subCreatorLine = -1
	public var creatorAs: String?
	public var seriesLine = -1
	public var publisherLine = -1
	public var publisher: String?

	public var titleEndLine = -1
	var firstCommentLineNum = -1
	public var modified = Date()
	public var vertical = true
	public var rtl = false

	public let srcFile: URL
	/// Text entry path inside an archive.
	public var textEntryName: String?
	public var firstImageLineNum = -1
	public var firstImageIdx = -1

	/// Cover file path or URL. "" = first illustration, nil = no cover.
	public var coverFileName: String?
	/// Edited (cropped) cover; takes precedence over coverFileName.
	public var coverImage: CGImage?
	/// Index of the illustration used as cover, -1 for none.
	public var coverImageIndex = -1
	public var coverExt: String?
	public var insertCoverPage = false
	public var insertCoverPageToc = false
	public var insertTitlePage = false
	public var insertTocPage = false
	public var tocVertical = false
	public var insertTitleToc = true
	public var imageOnly = false

	var mapImageSectionLine: [Int: String] = [:]
	var mapPageBreakLine = Set<Int>()
	var mapNoPageBreakLine = Set<Int>()
	var mapIgnoreLine = Set<Int>()
	var mapChapterLine: [Int: ChapterLineInfo] = [:]

	public init(_ srcFile: URL) {
		self.srcFile = srcFile
	}

	func addImageSectionLine(_ lineNum: Int, _ imageFileName: String?) { mapImageSectionLine[lineNum] = imageFileName ?? "" }
	func isImageSectionLine(_ lineNum: Int) -> Bool { mapImageSectionLine[lineNum] != nil }
	func getImageSectionFileName(_ lineNum: Int) -> String? { mapImageSectionLine[lineNum] }
	func addPageBreakLine(_ lineNum: Int) { mapPageBreakLine.insert(lineNum) }
	func isPageBreakLine(_ lineNum: Int) -> Bool { mapPageBreakLine.contains(lineNum) }
	func addNoPageBreakLine(_ lineNum: Int) { mapNoPageBreakLine.insert(lineNum) }
	func isNoPageBreakLine(_ lineNum: Int) -> Bool { mapNoPageBreakLine.contains(lineNum) }
	func addIgnoreLine(_ lineNum: Int) { mapIgnoreLine.insert(lineNum) }
	func isIgnoreLine(_ lineNum: Int) -> Bool { mapIgnoreLine.contains(lineNum) }

	func addChapterLineInfo(_ info: ChapterLineInfo) { mapChapterLine[info.lineNum] = info }
	public func removeChapterLineInfo(_ lineNum: Int) { mapChapterLine[lineNum] = nil }
	public func getChapterLineInfo(_ lineNum: Int) -> ChapterLineInfo? { mapChapterLine[lineNum] }
	func getChapterLevel(_ lineNum: Int) -> Int { mapChapterLine[lineNum]?.level ?? 0 }

	/// TOC candidates sorted by line.
	public var chapterLineInfoList: [ChapterLineInfo] {
		mapChapterLine.keys.sorted().compactMap { mapChapterLine[$0] }
	}

	/// Drops runs of auto-detected headings (a table of contents in the text itself).
	func excludeTocChapter() {
		var excludeLine = Set<Int>()
		for lineNum in mapChapterLine.keys where isPattern(lineNum) {
			var prevIsPattern = false
			if isPattern(lineNum - 1) { prevIsPattern = true }
			else if mapChapterLine[lineNum]!.emptyNext && isPattern(lineNum - 2) { prevIsPattern = true }
			var nextIsPattern = false
			if isPattern(lineNum + 1) { nextIsPattern = true }
			else if isPattern(lineNum + 2) { nextIsPattern = true }
			if prevIsPattern && nextIsPattern { excludeLine.insert(lineNum) }
		}
		var excludeLine2 = Set<Int>()
		for lineNum in mapChapterLine.keys where !excludeLine.contains(lineNum) && isPattern(lineNum) {
			if excludeLine.contains(lineNum - 1) { excludeLine2.insert(lineNum) }
			else if mapChapterLine[lineNum]!.emptyNext && excludeLine.contains(lineNum - 2) { excludeLine2.insert(lineNum) }
			else if excludeLine.contains(lineNum + 1) { excludeLine2.insert(lineNum) }
			else if excludeLine.contains(lineNum + 2) { excludeLine2.insert(lineNum) }
		}
		for l in excludeLine { mapChapterLine[l] = nil }
		for l in excludeLine2 { mapChapterLine[l] = nil }
	}

	private func isPattern(_ num: Int) -> Bool { mapChapterLine[num]?.isPattern ?? false }

	private func metaLine(_ line: Int) -> String? {
		guard line != -1 else { return nil }
		let i = line - metaLineStart
		return i >= 0 && i < metaLines.count ? metaLines[i] : nil
	}
	var titleText: String? { metaLine(titleLine) }
	var subTitleText: String? { metaLine(subTitleLine) }
	var orgTitleText: String? { metaLine(orgTitleLine) }
	var subOrgTitleText: String? { metaLine(subOrgTitleLine) }
	var creatorText: String? { metaLine(creatorLine) }
	var subCreatorText: String? { metaLine(subCreatorLine) }
	var seriesText: String? { metaLine(seriesLine) }
	var publisherText: String? { metaLine(publisherLine) }

	/// Sets title/author from the first lines of the text.
	func setMetaInfo(_ titleType: TitleType, _ pubFirst: Bool, _ metaLines: [String?], _ metaLineStartIn: Int, _ firstCommentLineNum: Int) {
		self.firstCommentLineNum = firstCommentLineNum
		titleLine = -1; orgTitleLine = -1; subTitleLine = -1; subOrgTitleLine = -1
		creatorLine = -1; subCreatorLine = -1; publisherLine = -1
		title = ""; titleAs = nil; creator = ""; creatorAs = nil; publisher = nil

		guard titleType != .none else { return }
		self.metaLines = metaLines
		self.metaLineStart = metaLineStartIn
		var metaLineStart = metaLineStartIn
		// Java indexes past the 10-line buffer freely, relying on exceptions being impossible
		// for these offsets; out-of-range reads return nil here.
		func m(_ i: Int) -> String? { i >= 0 && i < metaLines.count ? metaLines[i] : nil }
		func ms(_ i: Int) -> String { m(i) ?? "null" }

		var linesLength = 0
		for i in 0..<metaLines.count {
			if metaLines[i] == nil || metaLines[i]!.jlen == 0 { linesLength = i; break }
		}
		var arrIndex = 0
		if pubFirst && linesLength >= 2 {
			publisherLine = metaLineStart
			publisher = metaLines[0]
			metaLineStart += 1
			linesLength -= 1
			arrIndex += 1
		}
		if linesLength > 0 && titleType == .titleOnly {
			titleLine = metaLineStart
			title = m(0 + arrIndex)
			titleEndLine = metaLineStart
		} else if linesLength > 0 && titleType == .titleAuthorOnly {
			titleLine = metaLineStart
			title = m(0 + arrIndex)
			creator = m(1 + arrIndex)
			titleEndLine = metaLineStart + 1
		} else {
			switch min(6, linesLength) {
			case 6:
				if titleType.titleFirst {
					titleLine = metaLineStart; orgTitleLine = metaLineStart + 1; subTitleLine = metaLineStart + 2; subOrgTitleLine = metaLineStart + 3
					title = ms(0 + arrIndex) + " " + ms(2 + arrIndex)
					titleEndLine = metaLineStart + 3
					if titleType.hasAuthor {
						creatorLine = metaLineStart + 4; subCreatorLine = metaLineStart + 5
						creator = m(4 + arrIndex)
						titleEndLine = metaLineStart + 5
					}
				} else {
					creatorLine = metaLineStart; subCreatorLine = metaLineStart + 1
					creator = m(0 + arrIndex)
					titleEndLine = metaLineStart + 1
					if titleType.hasTitle {
						titleLine = metaLineStart + 2; orgTitleLine = metaLineStart + 3; subTitleLine = metaLineStart + 4; subOrgTitleLine = metaLineStart + 5
						title = ms(2 + arrIndex) + " " + ms(4 + arrIndex)
						titleEndLine = metaLineStart + 5
					}
				}
			case 5:
				if titleType.titleFirst {
					titleLine = metaLineStart; orgTitleLine = metaLineStart + 1; subTitleLine = metaLineStart + 2
					title = ms(0 + arrIndex) + " " + ms(2 + arrIndex)
					titleEndLine = metaLineStart + 2
					if titleType.hasAuthor {
						creatorLine = metaLineStart + 3; subCreatorLine = metaLineStart + 4
						creator = m(3 + arrIndex)
						titleEndLine = metaLineStart + 4
					}
				} else {
					creatorLine = metaLineStart
					creator = m(0 + arrIndex)
					titleEndLine = metaLineStart
					if titleType.hasTitle {
						titleLine = metaLineStart + 1; orgTitleLine = metaLineStart + 2; subTitleLine = metaLineStart + 3; subOrgTitleLine = metaLineStart + 4
						title = ms(1 + arrIndex) + " " + ms(3 + arrIndex)
					}
					titleEndLine = metaLineStart + 4
				}
			case 4:
				if titleType.titleFirst {
					titleLine = metaLineStart; subTitleLine = metaLineStart + 1
					title = ms(0 + arrIndex) + " " + ms(1 + arrIndex)
					titleEndLine = metaLineStart + 1
					if titleType.hasAuthor {
						creatorLine = metaLineStart + 2; subCreatorLine = metaLineStart + 3
						creator = m(2 + arrIndex)
						titleEndLine = metaLineStart + 3
					}
				} else {
					creatorLine = metaLineStart; subCreatorLine = metaLineStart + 1
					creator = m(0 + arrIndex)
					titleEndLine = metaLineStart + 1
					if titleType.hasTitle {
						titleLine = metaLineStart + 2; subTitleLine = metaLineStart + 3
						title = ms(2 + arrIndex) + " " + ms(3 + arrIndex)
						titleEndLine = metaLineStart + 3
					}
				}
			case 3:
				if titleType.titleFirst {
					titleLine = metaLineStart; subTitleLine = metaLineStart + 1
					title = ms(0 + arrIndex) + " " + ms(1 + arrIndex)
					titleEndLine = metaLineStart + 1
					if titleType.hasAuthor {
						// 副著者を文字列で判断 (note: Java checks metaLines[1] without arrIndex)
						let third = ms(2 + arrIndex)
						if titleType != .subtitleAuthor && !(m(1)?.startsWith("―") ?? false) &&
							(third.endsWith("訳") || third.endsWith("編纂") || third.endsWith("校訂")) {
							titleLine = metaLineStart
							title = m(0 + arrIndex)
							subTitleLine = -1
							creatorLine = metaLineStart + 1
							creator = m(1 + arrIndex)
							subCreatorLine = metaLineStart + 2
						} else {
							creatorLine = metaLineStart + 2
							creator = m(2 + arrIndex)
						}
						titleEndLine = metaLineStart + 2
					}
				} else {
					creatorLine = metaLineStart
					creator = m(0 + arrIndex)
					titleEndLine = metaLineStart
					if titleType.hasTitle {
						titleLine = metaLineStart + 1; subTitleLine = metaLineStart + 2
						title = ms(1 + arrIndex) + " " + ms(2 + arrIndex)
						titleEndLine = metaLineStart + 2
					}
				}
			case 2:
				if titleType.titleFirst {
					titleLine = metaLineStart
					title = m(0 + arrIndex)
					if titleType.hasAuthor {
						if firstCommentLineNum > 0 && firstCommentLineNum <= 6, let l3 = m(3 + arrIndex), l3.jlen > 0, (m(4 + arrIndex) ?? "").jlen == 0 {
							titleLine = metaLineStart; subTitleLine = metaLineStart + 1
							title = ms(0 + arrIndex) + " " + ms(1 + arrIndex)
							creatorLine = metaLineStart + 3
							creator = m(2 + arrIndex)
							titleEndLine = metaLineStart + 3
						} else {
							creatorLine = metaLineStart + 1
							creator = m(1 + arrIndex)
							titleEndLine = metaLineStart + 1
						}
					}
				} else {
					creatorLine = metaLineStart
					creator = m(0 + arrIndex)
					if titleType.hasTitle {
						titleLine = metaLineStart + 1
						title = m(1 + arrIndex)
					}
					titleEndLine = metaLineStart + 1
				}
			case 1:
				if titleType.titleFirst {
					titleLine = metaLineStart
					title = m(0 + arrIndex)
					titleEndLine = metaLineStart
					if titleType.hasAuthor, let l2 = m(2 + arrIndex), l2.jlen > 0, (m(3 + arrIndex) ?? "").jlen == 0 {
						creatorLine = metaLineStart + 2
						creator = l2
						titleEndLine = metaLineStart + 2
					}
				} else {
					creatorLine = metaLineStart
					creator = m(0 + arrIndex)
					titleEndLine = metaLineStart
					if titleType.hasTitle, let l2 = m(2 + arrIndex), l2.jlen > 0, (m(3 + arrIndex) ?? "").jlen == 0 {
						titleLine = metaLineStart + 2
						title = l2
						titleEndLine = metaLineStart + 2
					}
				}
			default:
				break
			}
		}
		if let c = creator, c.startsWith("―") || c.startsWith("【") { creator = nil }
		if let t = title { title = CharUtils.getChapterName(CharUtils.removeRuby(t), 0, false) }
		if let c = creator { creator = CharUtils.getChapterName(CharUtils.removeRuby(c), 0) }
	}

	/// Re-reads the title lines with a different title type (confirm sheet "reload").
	public func reloadMetadata(_ titleType: TitleType, _ pubFirst: Bool) {
		setMetaInfo(titleType, pubFirst, metaLines, metaLineStart, firstCommentLineNum)
	}

	/// Title and author from a file name like "[著者] 表題.txt".
	public static func fileTitleCreator(_ fileName: String) -> (title: String?, creator: String?) {
		var noExtName = fileName.replaceAll("\\.([A-Z]|[a-z]|[0-9])+$", "").replaceAll("\\.([A-Z]|[a-z]|[0-9])+$", "")
		noExtName = noExtName.replaceAll("（", "(").replaceAll("）", ")")
		noExtName = noExtName.replaceAll("\\(青空[^\\)]*\\)", "")
		noExtName = noExtName.replaceAll("\\([^\\)]*(校正|軽量|表紙|挿絵|補正|修正|ルビ|Rev|rev)[^\\)]*\\)", "")
		var title: String?
		var creator: String?
		let m = JPattern.compile("[\\[|［](.+?)[\\]|］][ |　]*(.*)[ |　]*$").matcher(noExtName)
		if m.find() {
			title = m.group(2)
			creator = m.group(1)
		} else {
			let m2 = JPattern.compile("^(.*?)( |　)*(\\(|（)").matcher(noExtName)
			title = m2.find() ? m2.group(1) : noExtName
		}
		title = title?.jtrim(); if title?.isEmpty == true { title = nil }
		creator = creator?.jtrim(); if creator?.isEmpty == true { creator = nil }
		return (title, creator)
	}

	public func vproperty(_ name: String) -> VValue {
		switch name {
		case "title": return .from(title)
		case "creator": return .from(creator)
		case "vertical": return .bool(vertical)
		case "rtl": return .bool(rtl)
		case "insertcoverpage": return .bool(insertCoverPage)
		case "insertcoverpagetoc": return .bool(insertCoverPageToc)
		case "inserttitlepage": return .bool(insertTitlePage)
		case "inserttocpage": return .bool(insertTocPage)
		case "tocvertical": return .bool(tocVertical)
		case "imageonly": return .bool(imageOnly)
		case "titleline": return .int(titleLine)
		case "creatorline": return .int(creatorLine)
		default: return .undefined
		}
	}
}
