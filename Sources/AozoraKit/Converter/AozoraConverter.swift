import Foundation

/// Converts Aozora Bunko annotated text into EPUB3 XHTML (port of `AozoraEpub3Converter`).
///
/// This is deliberately a close transliteration of the Java source, quirks included:
/// the goal is identical output, verified against the Java build by the golden tests.
final class AozoraConverter {
	// MARK: Options

	var noIllust = false
	var imageFloatPage = false
	var imageFloatBlock = false
	var withMarkId = false
	var autoYoko = true
	var autoYokoNum1 = true
	var autoYokoNum3 = true
	var autoYokoEQ1 = true
	var autoYokoEQ3 = true
	var chukiRuby = false
	var chukiKogaki = false
	var commentPrint = false
	var commentConvert = false
	var chapterSection = true
	/// 0 = as is, 1 = overlay, 2 = font
	var dakutenType = 1
	var printIvsBMP = false
	var printIvsSSP = true
	var separateColophon = true
	/// 0 = as is, 1 = fullsp span, 2 = U+2000 pair
	var spaceHyphenation = 0
	var removeEmptyLine = 0
	var maxEmptyLine = Int.max
	var forceIndent = false

	var forcePageBreak = false
	var forcePageBreakSize = 0
	var forcePageBreakEmptyLine = 0
	var forcePageBreakEmptySize = 0
	var forcePageBreakChapterLevel = 0
	var forcePageBreakChapterSize = 0

	var autoChapterName = false
	var autoChapterNumOnly = false
	var autoChapterNumTitle = false
	var autoChapterNumParen = false
	var autoChapterNumParenTitle = false
	var excludeSeqencialChapter = true
	var useNextLineChapterName = true
	var maxChapterNameLength = 64
	var chapterPattern: JPattern?
	var canceled = false

	let chapterNumChar: Set<JChar> = Set("0123456789０１２３４５６７８９〇一二三四五六七八九十百壱弐参肆伍ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩⅪⅫ".utf16)
	let chapterSeparator: Set<JChar> = Set(" 　-－「―『（".utf16)
	let chapterName = ["プロローグ", "エピローグ", "モノローグ", "序", "序章", "序　章", "終章", "終　章", "間章", "間　章", "転章", "転　章", "幕間", "幕　間"]
	let chapterNumPrefix = ["第", "その", ""]
	let chapterNumSuffix = [["話", "章", "篇", "部", "節", "幕", "編"], [""], ["章"]]
	let chapterNumParenPrefix = ["（", "〈", "〔", "【"]
	let chapterNumParenSuffix = ["）", "〉", "〕", "】"]
	var chapterChukiMap: [String: ChapterLineInfo.Kind] = [:]

	// MARK: State

	var inJisage = -1
	var inYoko = false
	var noTcyStart = Set<Int>()
	var noTcyEnd = Set<Int>()

	static let chukiPattern = "(［＃.+?］)|(<.+?>)"
	static let gaijiChukiPattern = "(※［＃.+?］)|(〔.+?〕)|(／″?＼)"
	static let chukiSufPattern = "［＃「([^］]+)」([^」|^］]+)］"
	static let chukiSufPattern2 = "［＃「([^］]+)」([^」|^］]*「[^」|^］]+」[^」|^］]*)］"
	static let chukiLeftPattern = "^［＃(.+?)］"
	static let chukiPatternMap: [String: String] = [
		"折り返し": "^［＃ここから([０-９]+)字下げ、折り返して([０-９]+)字下げ(.*)］",
		"字下げ字詰め": "^［＃ここから([０-９]+)字下げ、([０-９]+)字詰め.*］",
		"字下げ複合": "^［＃ここから([０-９]+)字下げ.*］",
		"字下げ終わり複合": "^［＃ここで字下げ.*終わり",
	]

	let t = ChukiTables.shared
	let gaijiConverter = GaijiConverter.shared
	let latinConverter = LatinConverter.shared

	/// replace.txt: single characters and two-character sequences
	var replaceMap: [JChar: String]?
	var replace2Map: [String: String]?

	/// Single-glyph gaiji fonts found in the gaiji directory.
	var utf16FontMap: [Int: String]?
	var utf32FontMap: [Int: String]?
	var ivs16FontMap: [String: String]?
	var ivs32FontMap: [String: String]?

	let writer: EpubWriter
	let log: Log

	var bookInfo: BookInfo!
	/// Vertical text (mirrors bookInfo.vertical; the writer switches it for title/TOC output).
	var vertical = true
	var lineNum = 0
	var pageByteSize = 0
	var sectionCharLength = 0
	var lineIdNum = 0
	var tagLevel = 0
	var nextLineIsCaption = false
	var inImageTag = false

	let pageBreakNormal = PageBreakType(true, 0, PageBreakType.imagePageNone)
	let pageBreakMiddle = PageBreakType(true, PageBreakType.pageMiddle, PageBreakType.imagePageNone)
	let pageBreakBottom = PageBreakType(true, PageBreakType.pageBottom, PageBreakType.imagePageNone)
	let pageBreakImageAuto = PageBreakType(true, 0, PageBreakType.imagePageAuto)
	let pageBreakImageW = PageBreakType(true, 0, PageBreakType.imagePageW)
	let pageBreakImageH = PageBreakType(true, 0, PageBreakType.imagePageH)
	let pageBreakImageNoFit = PageBreakType(true, 0, PageBreakType.imagePageNoFit)
	let pageBreakNoChapter = PageBreakType(true, 0, PageBreakType.imagePageNone, true)

	var pageBreakTrigger: PageBreakType?
	var skipMiddleEmpty = false
	var printEmptyLines = 0
	var lastChapterLine = -1

	/// - Parameters:
	///   - replaceFile: optional replace.txt (tab-separated character substitutions)
	///   - gaijiDirectory: folder of single-glyph fonts named u<hex>.ttf / u<hex>-u<ivs>.ttf
	init(writer: EpubWriter, log: Log, replaceFile: URL? = nil, gaijiDirectory: URL = AozoraResources.gaijiDirectory) {
		self.writer = writer
		self.log = log

		if let replaceFile, let lines = try? TextIO.readLines(replaceFile) {
			var map: [JChar: String] = [:], map2: [String: String] = [:]
			for (n, line) in lines.enumerated() where line.jlen > 0 && line.charAt(0) != "#" {
				let values = line.split(regex: "\t")
				guard values.count > 1 else { log.error(n + 1 - 1, replaceFile.lastPathComponent, line); continue }
				if values[0].jlen == 1 { map[values[0].charAt(0)] = values[1] }
				else if values[0].jlen == 2 { map2[values[0]] = values[1] }
				else { log.error(n, replaceFile.lastPathComponent + " too long ", line) }
			}
			replaceMap = map
			replace2Map = map2
		}

		writer.gaijiFontDirectory = gaijiDirectory
		loadGaijiFonts(gaijiDirectory)
	}

	private func loadGaijiFonts(_ dir: URL) {
		guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
		var u16: [Int: String] = [:], u32: [Int: String] = [:], i16: [String: String] = [:], i32: [String: String] = [:]
		for file in files where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
			let fileName = file.lastPathComponent.lowercased()
			let ext = (fileName as NSString).pathExtension
			guard ["ttf", "ttc", "otf"].contains(ext), fileName.hasPrefix("u") else { continue }
			let className = String(fileName.dropFirst().dropLast(ext.count + 1))
			if fileName.indexOf("-u") > 0 {
				let strs = className.split(regex: "-u")
				guard strs.count == 2, let c0 = Int(strs[0], radix: 16), let c1 = Int(strs[1], radix: 16), 0xE0100 <= c1 && c1 <= 0xE01EF else {
					log.warn(-1, "IVS以外の合成フォントは対応しません", file.lastPathComponent)
					continue
				}
				if c0 < 0xFFFF { i16["u" + className] = file.lastPathComponent } else { i32["u" + className] = file.lastPathComponent }
			} else {
				let code = Int(className, radix: 16) ?? 0
				if code <= 0xFFFF { u16[code] = file.lastPathComponent } else { u32[code] = file.lastPathComponent }
			}
		}
		utf16FontMap = u16.isEmpty ? nil : u16
		utf32FontMap = u32.isEmpty ? nil : u32
		ivs16FontMap = i16.isEmpty ? nil : i16
		ivs32FontMap = i32.isEmpty ? nil : i32
	}

	func getChukiValue(_ key: String) -> [String]? { t.chukiMap[key] }

	func setRemoveEmptyLine(_ removeEmptyLine: Int, _ maxEmptyLine: Int) {
		self.removeEmptyLine = removeEmptyLine
		self.maxEmptyLine = maxEmptyLine == 0 ? Int.max : maxEmptyLine
	}

	func setChapterLevel(maxLength: Int, excludeSeqencialChapter: Bool, useNextLineChapterName: Bool, section: Bool,
	                     h: Bool, h1: Bool, h2: Bool, h3: Bool, sameLineChapter: Bool,
	                     chapterName: Bool, numOnly: Bool, numTitle: Bool, numParen: Bool, numParenTitle: Bool,
	                     pattern: String) {
		maxChapterNameLength = maxLength
		chapterSection = section
		chapterChukiMap.removeAll()
		if h {
			chapterChukiMap["ここから見出し"] = .chukiH
			chapterChukiMap["見出し"] = .chukiH
			if sameLineChapter { chapterChukiMap["同行見出し"] = .chukiH }
		}
		if h1 {
			chapterChukiMap["ここから大見出し"] = .chukiH1
			chapterChukiMap["大見出し"] = .chukiH1
			if sameLineChapter { chapterChukiMap["同行大見出し"] = .chukiH1 }
		}
		if h2 {
			chapterChukiMap["ここから中見出し"] = .chukiH2
			chapterChukiMap["中見出し"] = .chukiH2
			if sameLineChapter { chapterChukiMap["同行中見出し"] = .chukiH2 }
		}
		if h3 {
			chapterChukiMap["ここから小見出し"] = .chukiH3
			chapterChukiMap["小見出し"] = .chukiH3
			if sameLineChapter { chapterChukiMap["同行小見出し"] = .chukiH3 }
		}
		self.useNextLineChapterName = useNextLineChapterName
		self.excludeSeqencialChapter = excludeSeqencialChapter
		autoChapterName = chapterName
		autoChapterNumOnly = numOnly
		autoChapterNumTitle = numTitle
		autoChapterNumParen = numParen
		autoChapterNumParenTitle = numParenTitle
		chapterPattern = nil
		if !pattern.isEmpty {
			chapterPattern = JPattern.tryCompile(pattern)
			if chapterPattern == nil { log.println("[WARN] 目次抽出のその他パターンが正しくありません: " + pattern) }
		}
	}

	func setForcePageBreak(_ size: Int, _ emptyLine: Int, _ emptySize: Int, _ chapterLevel: Int, _ chapterSize: Int) {
		forcePageBreakSize = size
		forcePageBreakEmptyLine = emptyLine
		forcePageBreakEmptySize = emptySize
		forcePageBreakChapterLevel = chapterLevel
		forcePageBreakChapterSize = chapterSize
		forcePageBreak = size > 0 || (emptyLine > 0 && emptySize > 0) || (chapterLevel > 0 && chapterSize > 0)
		if emptyLine > 0 { forcePageBreakSize = max(forcePageBreakSize, emptySize) }
		if chapterLevel > 0 { forcePageBreakSize = max(forcePageBreakSize, chapterSize) }
	}

	// MARK: - Pre-scan

	/// Reads title/author, TOC candidates and image references (Java `getBookInfo`).
	func getBookInfo(_ srcFile: URL, _ lines: [String], _ imageInfoReader: ImageInfoReader, _ titleType: TitleType, _ pubFirst: Bool) -> BookInfo {
		let bookInfo = BookInfo(srcFile)
		lineNum = -1
		var preLines: [String?] = [nil, nil]
		var inComment = false
		var firstCommentStarted = false
		var firstCommentLineNum = -1
		var firstLines = [String?](repeating: nil, count: 10)
		var firstLineStart = -1
		var commentLineNum = 0
		var commentLineStart = -1
		var lastEmptyLine = -1
		let autoChapter = autoChapterName || autoChapterNumTitle || autoChapterNumOnly || autoChapterNumParen || autoChapterNumParenTitle || chapterPattern != nil
		var addSectionChapter = true
		var addChapterName = false
		var addNextChapterName = -1
		var preChapterLineInfo: ChapterLineInfo? = nil

		for rawLine in lines {
			lineNum += 1
			let line = CharUtils.removeSpace(replaceChukiSufTag(convertGaijiChuki(rawLine, true, false)))
			let noRubyLine = CharUtils.removeRuby(line)

			if noRubyLine.startsWith("--------------------------------") {
				if !noRubyLine.startsWith("--------------------------------------------------") {
					log.warn(lineNum, "コメント行の文字数が足りません")
				} else {
					if firstCommentLineNum == -1 { firstCommentLineNum = lineNum }
					firstCommentStarted = true
					if inComment {
						if commentLineNum > 20 { log.warn(lineNum, "コメントが \(commentLineNum) 行 (\(commentLineStart + 1)) -") }
						commentLineNum = 0
						inComment = false
						continue
					} else {
						if lineNum > 10 && !(commentPrint && commentConvert) { log.warn(lineNum, "コメント開始行が10行目以降にあります") }
						commentLineStart = lineNum
						inComment = true
						continue
					}
				}
				if inComment { commentLineNum += 1 }
			}

			if noRubyLine.isEmpty || noRubyLine.jequals(" ") || noRubyLine.jequals("　") {
				lastEmptyLine = lineNum
				continue
			}

			if inComment && !commentPrint { continue }

			if !noIllust { checkImageOnly(bookInfo, preLines, noRubyLine, lineNum) }

			if addChapterName {
				if let pre = preChapterLineInfo {
					let name = getChapterName(noRubyLine)
					if name.jlen > 0 {
						pre.chapterName = name
						pre.lineNum = lineNum
						addChapterName = false
						if useNextLineChapterName { addNextChapterName = lineNum + 1 }
						addSectionChapter = false
					}
					preChapterLineInfo = nil
				} else {
					addChapterName = false
				}
			}

			let m = JPattern.compile(Self.chukiPattern).matcher(noRubyLine)
			while m.find() {
				let chukiTag = m.group()
				let chukiName = chukiTag.jsub(2, chukiTag.jlen - 1)
				if t.flagPageBreak.contains(chukiName) {
					addSectionChapter = true
				} else if let chapterType = chapterChukiMap[chukiName] {
					if noRubyLine.jlen == m.start() + chukiTag.jlen {
						let info = ChapterLineInfo(lineNum + 1, chapterType, addSectionChapter, ChapterLineInfo.getLevel(chapterType), lastEmptyLine == lineNum - 1)
						preChapterLineInfo = info
						bookInfo.addChapterLineInfo(info)
						addChapterName = true
						addNextChapterName = -1
					} else {
						bookInfo.addChapterLineInfo(ChapterLineInfo(lineNum, chapterType, addSectionChapter, ChapterLineInfo.getLevel(chapterType), lastEmptyLine == lineNum - 1, getChapterName(noRubyLine.jsub(m.end()))))
						if useNextLineChapterName { addNextChapterName = lineNum + 1 }
						addChapterName = false
					}
					addSectionChapter = false
				}

				let lowerChukiTag = chukiTag.toLowerCase()
				let imageStartIdx = chukiTag.lastIndexOf("（")
				if imageStartIdx > -1 {
					let imageEndIdx = chukiTag.indexOf("）", imageStartIdx)
					let imageDotIdx = chukiTag.indexOf(".", imageStartIdx)
					if imageDotIdx > -1 && imageDotIdx < imageEndIdx, let imageFileName = getImageChukiFileName(chukiTag, imageStartIdx) {
						noteFirstImage(bookInfo, imageInfoReader, imageFileName)
					}
				} else if lowerChukiTag.startsWith("<img"), let imageFileName = getTagAttr(chukiTag, "src") {
					noteFirstImage(bookInfo, imageInfoReader, imageFileName)
				}
			}

			if autoChapter && bookInfo.getChapterLevel(lineNum) == 0 {
				let noChukiLine = CharUtils.removeSpace(CharUtils.removeTag(noRubyLine))
				let nc = noChukiLine.jchars
				if let chapterPattern, chapterPattern.matcher(noChukiLine).find() {
					bookInfo.addChapterLineInfo(ChapterLineInfo(lineNum, .pattern, addSectionChapter, ChapterLineInfo.getLevel(.pattern), lastEmptyLine == lineNum - 1, getChapterName(noRubyLine)))
					if useNextLineChapterName { addNextChapterName = lineNum + 1 }
					addSectionChapter = false
				}
				if autoChapterName {
					var isChapter = false
					for prefix in chapterName where noChukiLine.startsWith(prefix) {
						if nc.count == prefix.jlen { isChapter = true; break }
						else if chapterSeparator.contains(nc[prefix.jlen]) { isChapter = true; break }
					}
					if !isChapter {
						prefixLoop: for i in 0..<chapterNumPrefix.count {
							let prefix = chapterNumPrefix[i]
							if noChukiLine.startsWith(prefix) {
								var idx = prefix.jlen
								while nc.count > idx && chapterNumChar.contains(nc[idx]) { idx += 1 }
								if idx <= prefix.jlen { break prefixLoop }
								for suffix in chapterNumSuffix[i] {
									if !suffix.isEmpty {
										if noChukiLine.jsub(idx).startsWith(suffix) {
											idx += suffix.jlen
											if nc.count == idx { isChapter = true; break }
											else if chapterSeparator.contains(nc[idx]) { isChapter = true; break }
										}
									} else {
										if nc.count == idx { isChapter = true; break }
										else if chapterSeparator.contains(nc[idx]) { isChapter = true; break }
									}
								}
							}
						}
					}
					if isChapter {
						bookInfo.addChapterLineInfo(ChapterLineInfo(lineNum, .chapterName, addSectionChapter, ChapterLineInfo.getLevel(.chapterName), lastEmptyLine == lineNum - 1, getChapterName(noRubyLine)))
						if useNextLineChapterName { addNextChapterName = lineNum + 1 }
						addChapterName = false
						addSectionChapter = false
					}
				}
				if autoChapterNumOnly || autoChapterNumTitle {
					var idx = 0
					while nc.count > idx && chapterNumChar.contains(nc[idx]) { idx += 1 }
					if idx > 0 {
						if autoChapterNumOnly && nc.count == idx || autoChapterNumTitle && nc.count > idx && chapterSeparator.contains(nc[idx]) {
							bookInfo.addChapterLineInfo(ChapterLineInfo(lineNum, .chapterNum, addSectionChapter, ChapterLineInfo.getLevel(.chapterNum), lastEmptyLine == lineNum - 1, getChapterName(noRubyLine)))
							if useNextLineChapterName { addNextChapterName = lineNum + 1 }
							addChapterName = false
							addSectionChapter = false
						}
					}
				}
				if autoChapterNumParen || autoChapterNumParenTitle {
					for i in 0..<chapterNumParenPrefix.count {
						let prefix = chapterNumParenPrefix[i]
						if noChukiLine.startsWith(prefix) {
							var idx = prefix.jlen
							while nc.count > idx && chapterNumChar.contains(nc[idx]) { idx += 1 }
							if idx <= prefix.jlen { break }
							let suffix = chapterNumParenSuffix[i]
							if noChukiLine.jsub(idx).startsWith(suffix) {
								idx += suffix.jlen
								if autoChapterNumParen && nc.count == idx || autoChapterNumParenTitle && nc.count > idx && chapterSeparator.contains(nc[idx]) {
									bookInfo.addChapterLineInfo(ChapterLineInfo(lineNum, .chapterNum, addSectionChapter, 13, lastEmptyLine == lineNum - 1, getChapterName(noRubyLine)))
									if useNextLineChapterName { addNextChapterName = lineNum + 1 }
									addChapterName = false
									addSectionChapter = false
								}
							}
						}
					}
				}
			}

			if chapterSection && addSectionChapter {
				let u = noRubyLine.jchars
				if u.count > 2 && u[0] == "底" && u[1] == "本" && u[2] == "：" {
					addSectionChapter = false
				} else {
					let name = getChapterName(noRubyLine)
					if name.replaceAll("◇|◆|□|■|▽|▼|☆|★|＊|＋|×|†|　", "").jlen > 0 {
						bookInfo.addChapterLineInfo(ChapterLineInfo(lineNum, .pageBreak, true, 1, lastEmptyLine == lineNum - 1, name))
						if useNextLineChapterName { addNextChapterName = lineNum + 1 }
						addSectionChapter = false
					}
				}
			}

			if addNextChapterName == lineNum && bookInfo.getChapterLineInfo(lineNum) == nil {
				let name = getChapterName(noRubyLine)
				if name.jlen > 0 { bookInfo.getChapterLineInfo(lineNum - 1)?.joinChapterName(name) }
				addNextChapterName = -1
			}

			if !firstCommentStarted {
				let replaced = CharUtils.getChapterName(noRubyLine, 0)
				if firstLineStart == -1 {
					if replaced.jlen > 0 {
						firstLineStart = lineNum
						firstLines[0] = line
					}
				} else {
					if isPageBreakLine(noRubyLine) { firstCommentStarted = true }
					if lineNum - firstLineStart > firstLines.count - 1 {
						firstCommentStarted = true
					} else if replaced.jlen > 0 {
						firstLines[lineNum - firstLineStart] = line
					}
				}
			}
			preLines[1] = preLines[0]
			preLines[0] = noRubyLine
		}

		bookInfo.totalLineNum = lineNum
		if inComment { log.error(commentLineStart, "コメントが閉じていません") }

		bookInfo.setMetaInfo(titleType, pubFirst, firstLines, firstLineStart, firstCommentLineNum)

		if bookInfo.titleLine > -1 {
			let name = getChapterName(bookInfo.title ?? "")
			if let info = bookInfo.getChapterLineInfo(bookInfo.titleLine) {
				info.type = .title
				info.level = 0
			} else {
				bookInfo.addChapterLineInfo(ChapterLineInfo(bookInfo.titleLine, .title, true, 0, false, name))
			}
			if bookInfo.titleLine > 0 {
				for i in stride(from: bookInfo.titleLine - 1, through: 0, by: -1) { bookInfo.removeChapterLineInfo(i) }
			}
		}
		if bookInfo.orgTitleLine > 0 { bookInfo.removeChapterLineInfo(bookInfo.orgTitleLine) }
		if bookInfo.subTitleLine > 0 { bookInfo.removeChapterLineInfo(bookInfo.subTitleLine) }
		if bookInfo.subOrgTitleLine > 0 { bookInfo.removeChapterLineInfo(bookInfo.subOrgTitleLine) }

		if excludeSeqencialChapter { bookInfo.excludeTocChapter() }
		return bookInfo
	}

	private func noteFirstImage(_ bookInfo: BookInfo, _ reader: ImageInfoReader, _ imageFileName: String) {
		reader.addImageFileName(imageFileName)
		if bookInfo.firstImageLineNum == -1 {
			// small images (gaiji etc.) are ignored
			if let name = reader.correctExt(imageFileName), let info = reader.imageInfo(name), info.width > 64 && info.height > 64 {
				bookInfo.firstImageLineNum = lineNum
				bookInfo.firstImageIdx = reader.countImageFileNames - 1
			}
		}
	}

	func getChapterName(_ line: String) -> String { CharUtils.getChapterName(line, maxChapterNameLength) }

	private func isPageBreakLine(_ line: String) -> Bool {
		let m = JPattern.compile(Self.chukiLeftPattern).matcher(line)
		if m.find() { return t.flagPageBreak.contains(m.group(1) ?? "") }
		return false
	}

	/// Records an image that sits alone between two page breaks (single-page image).
	private func checkImageOnly(_ bookInfo: BookInfo, _ preLines: [String?], _ line: String, _ lineNum: Int) {
		guard let pre0 = preLines[0] else { return }
		if line.indexOf("］") <= 3 { return }
		let curChuki = line.jsub(2, line.indexOf("］"))
		guard t.flagPageBreak.contains(curChuki) else { return }
		let pre1 = preLines[1]
		if pre1 == nil || (pre1!.indexOf("］") > 3 && t.flagPageBreak.contains(pre1!.jsub(pre1!.lastIndexOf("＃") + 1, pre1!.jlen - 1))) {
			if (pre0.startsWith("［＃") && pre0.matches("^［＃.*（.+\\..+") && pre0.indexOf("］") == pre0.jlen - 1) ||
				(pre0.toLowerCase().startsWith("<img") && pre0.indexOf(">") == pre0.jlen - 1) {
				let fileName: String?
				if pre0.toLowerCase().startsWith("<img") {
					fileName = getTagAttr(pre0, "src")
				} else {
					fileName = getImageChukiFileName(pre0, pre0.indexOf("（"))
				}
				bookInfo.addImageSectionLine(lineNum - 1, fileName)
			}
		}
	}

	/// Attribute value from an HTML tag.
	func getTagAttr(_ tag: String, _ attr: String) -> String? {
		let lowerTag = tag.toLowerCase()
		let srcIdx = lowerTag.indexOf(" " + attr + "=")
		if srcIdx == -1 { return nil }
		var start = srcIdx + attr.jlen + 2
		guard start < lowerTag.jlen else { return nil }
		var end = -1
		if lowerTag.charAt(start) == "\"" { end = lowerTag.indexOf("\"", start + 1) }
		else if lowerTag.charAt(start) == "'" { end = lowerTag.indexOf("'", start + 1) }
		if end == -1 { end = lowerTag.indexOf(">", start); start -= 1 }
		if end == -1 { end = lowerTag.indexOf(" ", start); start -= 1 }
		if end != -1 { return tag.jsub(start + 1, end).jtrim() }
		return nil
	}

	func hasImageCaption(_ chukiTag: String) -> Bool { chukiTag.indexOf("キャプション付き") > 0 }

	/// File name inside an image chuki; startIdx is the position of '（'.
	func getImageChukiFileName(_ chukiTag: String, _ startIdx: Int) -> String? {
		var endIdx = chukiTag.indexOf("、", startIdx + 1)
		if endIdx == -1 { endIdx = chukiTag.indexOf("）", startIdx + 1) }
		else { endIdx = min(endIdx, chukiTag.indexOf("）", startIdx + 1)) }
		if startIdx < endIdx { return chukiTag.jsub(startIdx + 1, endIdx) }
		return nil
	}

	// MARK: - Conversion

	func cancel() { canceled = true }

	/// Converts the whole text, writing sections through the writer (Java `convertTextToEpub3`).
	func convertTextToEpub3(_ outIn: EpubWriter?, _ lines: [String], _ bookInfo: BookInfo) {
		let orgOut = outIn
		var out = outIn
		canceled = false
		self.bookInfo = bookInfo
		pageByteSize = 0
		sectionCharLength = 0
		lineNum = -1
		lineIdNum = 1
		tagLevel = 0
		inJisage = -1
		setPageBreakTrigger(pageBreakNormal)

		var lastZeroTagLevelLineNum = -1
		var preTitleBuf: [String] = []
		var inComment = false
		var skipTitle = false
		var noImage = false

		if bookInfo.titlePageType == .none || bookInfo.titlePageType == .middle || bookInfo.titlePageType == .horizontal {
			bookInfo.insertTitlePage = true
			skipTitle = true
			out = nil
			noImage = true
		}

		guard !lines.isEmpty else { return }
		for (index, rawLine) in lines.enumerated() {
			let line = index == 0 ? (CharUtils.removeBOM(rawLine) ?? "") : rawLine
			lineNum += 1

			if skipTitle {
				if bookInfo.metaLineStart > lineNum { preTitleBuf.append(line) }
				if bookInfo.metaLineStart == lineNum && !preTitleBuf.isEmpty {
					noImage = false
					if lastZeroTagLevelLineNum >= 0 {
						// flush lines before the title that were outside any block tag
						let lineNumBak = lineNum
						pageByteSize = 0
						sectionCharLength = 0
						lineNum = 0
						lineIdNum = 1
						tagLevel = 0
						inJisage = -1
						var i = 0
						while lineNum < lineNumBak {
							if lineNum <= lastZeroTagLevelLineNum {
								convertTextLineToEpub3(orgOut, preTitleBuf[i], lineNum, false, false)
							} else {
								convertTextLineToEpub3(out, preTitleBuf[i], lineNum, false, false)
							}
							i += 1
							lineNum += 1
						}
					}
					preTitleBuf.removeAll()
				}
				if bookInfo.titleEndLine + 1 == lineNum {
					if tagLevel > 0 { bookInfo.titleEndLine += 1 }
					else {
						skipTitle = false
						out = orgOut
						noImage = false
						bookInfo.addPageBreakLine(bookInfo.titleEndLine + 1)
					}
				}
			}

			if bookInfo.isPageBreakLine(lineNum) && sectionCharLength > 0 {
				if tagLevel == 0 { setPageBreakTrigger(pageBreakNormal) }
				else { bookInfo.addPageBreakLine(lineNum + 1) }
			}

			if line.startsWith("--------------------------------------------------") {
				if commentPrint {
					inComment.toggle()
				} else {
					inComment.toggle()
					continue
				}
			}
			if inComment {
				if commentPrint {
					if !commentConvert {
						let buf = JBuilder()
						for c in line.utf16 {
							switch c {
							case "&": buf.append("&amp;")
							case "<": buf.append("&lt;")
							case ">": buf.append("&gt;")
							default: buf.appendChar(c)
							}
						}
						printLineBuffer(out, buf, lineNum, false)
						continue
					}
				} else {
					continue
				}
			}

			if bookInfo.isIgnoreLine(lineNum) { continue }

			let titleTags: [(Int, String, String)] = [
				(bookInfo.titleLine, "表題前", "表題後"),
				(bookInfo.orgTitleLine, "原題前", "原題後"),
				(bookInfo.subTitleLine, "副題前", "副題後"),
				(bookInfo.subOrgTitleLine, "副原題前", "副原題後"),
				(bookInfo.creatorLine, "著者前", "著者後"),
				(bookInfo.subCreatorLine, "副著者前", "副著者後"),
			]
			if let (_, before, after) = titleTags.first(where: { $0.0 == lineNum }) {
				printLineBuffer(out, JBuilder(t.tag(before)), -1, true)
				convertTextLineToEpub3(out, line, lineNum, false, noImage)
				printLineBuffer(out, JBuilder(t.tag(after)), -1, true)
			} else {
				convertTextLineToEpub3(out, line, lineNum, false, noImage)
			}
			if canceled { return }
			if lineNum % 10 == 0 { writer.reportTextProgress(lineNum) }
			if tagLevel == 0 { lastZeroTagLevelLineNum = lineNum }
		}
	}

	// MARK: - Gaiji

	/// Converts gaiji chuki to characters; special characters get a ※ escape.
	func convertGaijiChuki(_ line: String, _ escape: Bool, _ logged: Bool = true) -> String {
		let m = JPattern.compile(Self.gaijiChukiPattern).matcher(line)
		guard m.find() else { return line }
		var begin = 0
		let buf = JBuilder()
		repeat {
			let chuki = m.group()
			let chukiStart = m.start()
			buf.append(line.jsub(begin, chukiStart))
			let first = chuki.charAt(0)
			if first == "※" {
				let chukiInner = chuki.jsub(3, chuki.jlen - 1)
				if chukiInner.startsWith("U+") || chukiInner.startsWith("u+"), let gaiji = gaijiConverter.codeToCharString(chukiInner) {
					buf.append(gaiji)
					begin = chukiStart + chuki.jlen
					continue
				}
				let chukiValues = chukiInner.split(regex: "、")
				var gaiji = gaijiConverter.toAlterString(chukiValues[0])
				if gaiji != nil && hasInnerChuki(line, m.start()) {
					gaiji = gaiji!.replaceAll(Self.chukiPattern, "")
				}
				if gaiji == nil && chukiValues.count > 3 { gaiji = gaijiConverter.codeToCharString(chukiValues[3]) }
				if gaiji == nil && chukiValues.count > 2 { gaiji = gaijiConverter.codeToCharString(chukiValues[2]) }
				if gaiji == nil && chukiValues.count > 1 { gaiji = gaijiConverter.codeToCharString(chukiValues[1]) }
				if gaiji == nil { gaiji = gaijiConverter.toUtf(chukiValues[0]) }
				if let g = gaiji {
					if g.jlen == 1 && escape {
						switch g.charAt(0) {
						case "※", "》", "《", "｜", "＃": buf.append("※")
						default: break
						}
					}
					buf.append(g)
					begin = chukiStart + chuki.jlen
					continue
				}
				let replacement: String
				if hasInnerChuki(line, m.start()) {
					replacement = "〓"
					log.warn(lineNum, "外字注記内に注記があります", chuki)
				} else {
					let imageStartIdx = chuki.indexOf("（", 2)
					if imageStartIdx > -1 && chuki.indexOf(".", 2) != -1 {
						// internal image chuki: ［＃（file）#GAIJI#］
						replacement = chuki.jsub(1, chuki.jlen - 1) + "#GAIJI#］"
					} else {
						if logged { log.info(lineNum, "外字未変換", chuki) }
						replacement = "〓［＃行右小書き］（" + chukiValues[0] + "）［＃行右小書き終わり］"
					}
				}
				buf.append(replacement)
			} else if first == "〔" {
				let inner = chuki.jsub(1, chuki.jlen - 1)
				if !CharUtils.isHalfSpace(inner.jchars) {
					buf.append("〔").append(convertGaijiChuki(inner, true)).append("〕")
				} else {
					buf.append(latinConverter.toLatinString(inner))
				}
			} else if first == "／" {
				buf.append(chuki.charAt(1) == "″" ? "〴" : "〳")
				buf.append("〵")
			}
			begin = chukiStart + chuki.jlen
		} while m.find()
		return buf.toString() + line.jsub(begin)
	}

	/// True if gaijiStart is inside an unclosed ［＃ chuki.
	private func hasInnerChuki(_ line: String, _ gaijiStart: Int) -> Bool {
		var startCount = 0
		var end = gaijiStart
		while true {
			end = line.lastIndexOf("［＃", end - 1)
			if end == -1 { break }
			startCount += 1
		}
		var endCount = 0
		end = gaijiStart
		while true {
			end = line.lastIndexOf("］", end - 1)
			if end == -1 { break }
			endCount += 1
		}
		return startCount > endCount
	}

	// MARK: - Forward-reference chuki

	/// Turns ［＃「target」は…］ into inline open/close chuki around the target.
	func replaceChukiSufTag(_ lineIn: String) -> String {
		if lineIn.indexOf("［＃「") == -1 { return lineIn }
		var line = lineIn

		// drop chuki nested inside chuki
		var buf = JBuilder()
		let mTag = JPattern.compile("((［＃)|］)").matcher(line)
		var mTagEnd = 0
		var innerTagLevel = 0
		var innerTagStart = 0
		while mTag.find() {
			if innerTagLevel <= 1 { buf.append(line.jsub(mTagEnd, mTag.start())) }
			mTagEnd = mTag.end()
			let tag = mTag.group()
			if tag.jequals("］") {
				if innerTagLevel <= 1 { buf.append(tag) }
				else if innerTagLevel == 2 { log.warn(lineNum, "注記内に注記があります", line.jsub(innerTagStart, mTagEnd)) }
				innerTagLevel -= 1
			} else {
				innerTagLevel += 1
				if innerTagLevel <= 1 { buf.append(tag) }
				else if innerTagLevel == 2 { innerTagStart = mTag.start() }
			}
		}
		buf.append(line.jsub(mTagEnd))
		line = buf.toString()

		var m = JPattern.compile(Self.chukiSufPattern).matcher(line)
		if !m.find() { return line }
		var chOffset = 0
		buf = JBuilder(line)
		repeat {
			let target = m.group(1) ?? ""
			let chuki = m.group(2) ?? ""
			let tags = t.sufChukiMap[chuki]
			var chukiTagStart = m.start()
			var chukiTagEnd = m.end()

			// ruby after the chuki: move it before
			if chukiTagEnd < line.jlen && buf.charAt(chukiTagEnd + chOffset) == "《" {
				let rubyEnd = buf.indexOf("》", chukiTagEnd + chOffset + 2)
				let ruby = buf.substring(chukiTagEnd + chOffset, rubyEnd + 1)
				buf.delete(chukiTagEnd + chOffset, rubyEnd + 1)
				buf.insert(chukiTagStart + chOffset, ruby)
				chukiTagStart += ruby.jlen
				chukiTagEnd += ruby.jlen
				log.warn(lineNum, "ルビが注記の後ろにあります", ruby)
			}

			if chuki.endsWith("の注記付き終わり") {
				buf.delete(chukiTagStart + chOffset, chukiTagEnd + chOffset)
				buf.insert(chukiTagStart + chOffset, "《" + target + "》")
				let start = buf.lastIndexOf("［＃注記付き］", chukiTagStart + chOffset)
				if start != -1 {
					buf.delete(start + 1, start + 7)
					buf.setCharAt(start, "｜")
					chOffset -= 6
				}
				chOffset += target.jlen + 2 - (chukiTagEnd - chukiTagStart)
			} else if let tags {
				let targetStart = getTargetStart(buf, chukiTagStart, chOffset, CharUtils.removeRuby(target).jlen)
				buf.delete(chukiTagStart + chOffset, chukiTagEnd + chOffset)
				buf.insert(chukiTagStart + chOffset, "［＃" + tags[1] + "］")
				buf.insert(targetStart, "［＃" + tags[0] + "］")
				chOffset += tags[0].jlen + tags[1].jlen + 6 - (chukiTagEnd - chukiTagStart)
			}
		} while m.find()

		line = buf.toString()
		m = JPattern.compile(Self.chukiSufPattern2).matcher(line)
		if !m.find() { return line }
		chOffset = 0
		repeat {
			let target = m.group(1) ?? ""
			let chuki = m.group(2) ?? ""
			let tags = t.sufChukiMap[chuki]
			let targetLength = target.jlen
			let chukiTagStart = m.start()
			let chukiTagEnd = m.end()
			if tags == nil {
				if chuki.endsWith("のルビ") || (chukiRuby && chuki.endsWith("の注記")) {
					if chuki.startsWith("に「") && !chuki.startsWith("に「ママ") {
						let targetStart = getTargetStart(buf, chukiTagStart, chOffset, targetLength)
						buf.delete(chukiTagStart + chOffset, chukiTagEnd + chOffset)
						let rt = chuki.jsub(chuki.indexOf("「") + 1, chuki.indexOf("」"))
						buf.insert(chukiTagStart + chOffset, "《" + rt + "》")
						buf.insert(targetStart, "｜")
						chOffset += rt.jlen + 3 - (chukiTagEnd - chukiTagStart)
					}
				} else if chukiKogaki && chuki.endsWith("の注記") {
					if chuki.startsWith("に「") && !chuki.startsWith("に「ママ") {
						buf.delete(chukiTagStart + chOffset, chukiTagEnd + chOffset)
						let kogaki = "［＃小書き］" + chuki.jsub(chuki.indexOf("「") + 1, chuki.indexOf("」")) + "［＃小書き終わり］"
						buf.insert(chukiTagStart + chOffset, kogaki)
						chOffset += kogaki.jlen - (chukiTagEnd - chukiTagStart)
					}
				}
			}
		} while m.find()
		return buf.toString()
	}

	/// Where to insert the opening tag of a forward-reference chuki.
	private func getTargetStart(_ buf: JBuilder, _ chukiTagStart: Int, _ chOffset: Int, _ targetLength: Int) -> Int {
		var idx = chukiTagStart - 1 + chOffset
		var hasRuby = false
		var length = 0
		while targetLength > length && idx >= 0 {
			switch buf.charAt(idx) {
			case "》":
				idx -= 1
				if CharUtils.isEscapedChar(buf, idx) { length += 1; break }
				while idx >= 0 && buf.charAt(idx) != "《" && !CharUtils.isEscapedChar(buf, idx) { idx -= 1 }
				hasRuby = true
			case "］":
				idx -= 1
				if CharUtils.isEscapedChar(buf, idx) { length += 1; break }
				while idx >= 0 && buf.charAt(idx) != "［" && !CharUtils.isEscapedChar(buf, idx) { idx -= 1 }
			case "｜":
				if CharUtils.isEscapedChar(buf, idx) { length += 1 }
			default:
				length += 1
			}
			idx -= 1
		}
		if hasRuby && idx >= 0 && buf.charAt(idx) == "｜" { return idx }
		return idx + 1
	}
}
