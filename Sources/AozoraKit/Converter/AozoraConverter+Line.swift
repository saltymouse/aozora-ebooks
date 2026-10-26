import Foundation

extension Array where Element == JChar {
	/// Bounds-checked read for spots where Java would have thrown (returns 0 instead of trapping).
	subscript(at i: Int) -> JChar { i >= 0 && i < count ? self[i] : 0 }
}

extension AozoraConverter {
	// MARK: - Title lines

	/// For the title page: converts only ruby, gaiji images and (vertical) tate-chu-yoko.
	func convertTitleLineToEpub3(_ line: String) -> String {
		let buf = JBuilder()
		var ch = line.jchars
		var charStart = 0
		let m = JPattern.compile(Self.chukiPattern).matcher(line)
		while m.find() {
			let chukiTag = m.group()
			let lowerChukiTag = chukiTag.toLowerCase()
			let chukiStart = m.start()
			if chukiTag.charAt(0) == "＃" { continue }
			if chukiTag.charAt(0) == "<" && !(lowerChukiTag.startsWith("<img ") || lowerChukiTag.startsWith("</img>") || lowerChukiTag.startsWith("<a ") || lowerChukiTag.startsWith("</a>")) { continue }
			let chukiName = chukiTag.jsub(2, chukiTag.jlen - 1)
			if charStart < chukiStart { convertEscapedText(buf, &ch, charStart, chukiStart) }
			if t.kunten.contains(chukiName) || (vertical && chukiName.startsWith("縦中横")) {
				buf.append(t.tag(chukiName))
			} else {
				let imageStartIdx = chukiTag.lastIndexOf("（")
				if imageStartIdx > -1 {
					if imageStartIdx == 2 && chukiTag.endsWith("）］") && chukiTag.indexOf(".", 2) == -1 {
						buf.append(t.tag("行右小書き"))
						buf.append(chukiTag.jsub(3, chukiTag.jlen - 2))
						buf.append(t.tag("行右小書き終わり"))
					} else if chukiTag.indexOf(".", 2) == -1 {
						// no extension
					} else if let srcFilePath = getImageChukiFileName(chukiTag, imageStartIdx), chukiTag.endsWith("#GAIJI#］") {
						if let fileName = writer.getImageFilePath(srcFilePath.jtrim(), -1) {
							buf.append(javaFormat(t.tag("外字画像"), fileName))
						} else {
							buf.append(javaFormat(t.tag("外字画像"), "null"))
						}
					}
				}
			}
			charStart = chukiStart + chukiTag.jlen
		}
		if charStart < ch.count { convertEscapedText(buf, &ch, charStart, ch.count) }
		return convertRubyText(buf.toString()).toString()
	}

	// MARK: - Body lines

	/// Converts one source line and writes it (Java `convertTextLineToEpub3`).
	func convertTextLineToEpub3(_ out: EpubWriter?, _ lineIn: String, _ lineNum: Int, _ noBrIn: Bool, _ noImage: Bool) {
		var noBr = noBrIn
		let buf = JBuilder()
		let line = replaceChukiSufTag(convertGaijiChuki(lineIn, true))

		if nextLineIsCaption {
			if !line.startsWith("［＃キャプション］") && !line.startsWith("［＃ここからキャプション］") {
				log.warn(lineNum, "画像の次の行にキャプションがありません")
				buf.append(t.tag("画像終わり"))
				buf.append("\n")
				inImageTag = false
			}
		}
		nextLineIsCaption = false

		var ch = line.jchars
		var charStart = 0

		// 行頭インデント: add a full-width space unless the line opens with a bracket etc.
		if forceIndent && ch.count > charStart + 1 {
			switch ch[charStart] {
			case "　", "「", "『", "（", "”", "〈", "【", "〔", "［", "※":
				break
			case " ", "\u{2000}":
				let c1 = ch[charStart + 1]
				if c1 == " " || c1 == "\u{2000}" || c1 == "　" { charStart += 1 }
				ch[charStart] = "　"
			default:
				buf.append("　")
			}
		}

		var wrcStart = 0
		var wrcBrPos = -1
		var wrcStartChar: JChar = 0
		var inMado = false
		var linkStarted = false
		let bufSuf = JBuilder()
		let m = JPattern.compile(Self.chukiPattern).matcher(line)

		noTcyStart.removeAll()
		noTcyEnd.removeAll()
		if inYoko { noTcyStart.insert(0) }

		while m.find() {
			let chukiTag = m.group()
			let lowerChukiTag = chukiTag.toLowerCase()
			var chukiStart = m.start()

			if chukiTag.charAt(0) == "＃" { continue }
			if chukiTag.charAt(0) == "<" && !(lowerChukiTag.startsWith("<img ") || lowerChukiTag.jequals("</img>") || lowerChukiTag.startsWith("<a ") || lowerChukiTag.jequals("</a>")) { continue }

			let chukiName = chukiTag.jsub(2, chukiTag.jlen - 1)
			let tags = t.chukiMap[chukiName]

			if wrcStart > 0 && chukiName.endsWith("割り注終わり") {
				var wrcEndChar: JChar = 0
				if wrcStartChar != 0 { wrcEndChar = ch[at: chukiStart - 1] }
				if charStart <= wrcBrPos && wrcBrPos <= chukiStart {
					convertEscapedText(buf, &ch, charStart, wrcBrPos)
					buf.append(t.tag("改行"))
					convertEscapedText(buf, &ch, wrcBrPos, chukiStart - (wrcEndChar == 0 ? 0 : 1))
					wrcBrPos = -1
				} else {
					convertEscapedText(buf, &ch, charStart, chukiStart - (wrcEndChar == 0 ? 0 : 1))
				}
				buf.append(tags?[0] ?? "")
				if wrcEndChar != 0 { buf.appendChar(wrcEndChar) }
				if wrcStart != -1 && chukiStart - wrcStart > 60 { log.warn(lineNum, "割り注が長すぎます") }
				wrcStart = -1
				wrcStartChar = 0
				wrcBrPos = -1
				charStart = chukiStart + chukiTag.jlen
				continue
			}

			if charStart < chukiStart {
				if charStart <= wrcBrPos && wrcBrPos <= chukiStart {
					convertEscapedText(buf, &ch, charStart, wrcBrPos)
					buf.append(t.tag("改行"))
					convertEscapedText(buf, &ch, wrcBrPos, chukiStart)
					wrcBrPos = -1
				} else {
					convertEscapedText(buf, &ch, charStart, chukiStart)
				}
			}

			if chukiName.endsWith("横組み") { inYoko = true; noTcyStart.insert(buf.length) }
			else if inYoko && chukiName.endsWith("横組み終わり") { inYoko = false; noTcyEnd.insert(buf.length) }
			if !inYoko && chukiName.startsWith("縦中横") {
				if chukiName.endsWith("終わり") { noTcyEnd.insert(buf.length) } else { noTcyStart.insert(buf.length) }
			}

			if let tags {
				var noTagAppend = false

				if t.flagPageBreak.contains(chukiName) && !bookInfo.isNoPageBreakLine(lineNum) {
					if inJisage >= 0 {
						log.warn(inJisage, "字下げ注記省略")
						buf.append(t.tag("字下げ省略"))
						inJisage = -1
					}
					if buf.length > 0 {
						printLineBuffer(out, convertRubyText(buf.toString()), lineNum, true)
						buf.setLength(0)
					}
					noBr = true
					if ch.count > charStart + chukiTag.jlen { noBr = false }

					if t.flagMiddle.contains(chukiName) {
						setPageBreakTrigger(pageBreakMiddle)
					} else if t.flagBottom.contains(chukiName) {
						setPageBreakTrigger(pageBreakBottom)
					} else if bookInfo.isImageSectionLine(lineNum + 1) {
						if writer.imageIndex == bookInfo.coverImageIndex && bookInfo.insertCoverPage {
							setPageBreakTrigger(nil)
						} else {
							setPageBreakTrigger(pageBreakImageAuto)
							pageBreakImageAuto.srcFileName = bookInfo.getImageSectionFileName(lineNum + 1)
							pageBreakImageAuto.imagePageType = writer.getImagePageType(pageBreakTrigger?.srcFileName, tagLevel, lineNum, hasImageCaption(chukiTag))
						}
					} else {
						setPageBreakTrigger(pageBreakNormal)
					}
				} else if chukiName.endsWith("字下げ") {
					if inJisage >= 0 {
						log.warn(inJisage, "字下げ注記省略")
						buf.append(t.tag("字下げ省略"))
						inJisage = -1
					}
					inJisage = tags.count > 1 ? -1 : lineNum
				} else if chukiName.endsWith("字下げ終わり") {
					if inJisage == -1 {
						log.info(lineNum, "字下げ終わり重複")
						noTagAppend = true
					}
					inJisage = -1
				} else if chukiName.startsWith("窓") {
					if !inMado && line.jsub(0, chukiStart).replaceAll("［＃[^］]+］", "").replaceAll("^( |　)*$", "").jlen > 0 {
						log.warn(lineNum, "行頭のみ対応: " + chukiName)
						noTagAppend = true
					} else {
						if inMado && chukiName.endsWith("終わり") { inMado = false } else { inMado = true }
					}
				} else if chukiName.endsWith("割り注") {
					wrcStart = chukiStart + chukiTag.jlen
					wrcStartChar = 0
					wrcBrPos = -1
					var wrcEnd = line.indexOf("［＃割り注終わり］", wrcStart)
					if wrcEnd == -1 { wrcEnd = line.indexOf("［＃ここで割り注終わり］", wrcStart) }
					if wrcEnd == -1 {
						log.error(lineNum, "割り注終わりなし")
						wrcStart = -1
					} else {
						if chukiStart == 0 || ch[at: chukiStart - 1] != "〔" && ch[at: chukiStart - 1] != "（" {
							if (ch[at: wrcStart] == "〔" && line.indexOf("〕", wrcStart) == wrcEnd - 1) || (ch[at: wrcStart] == "（" && line.indexOf("）", wrcStart) == wrcEnd - 1) {
								wrcStartChar = ch[wrcStart]
								buf.appendChar(ch[wrcStart])
								chukiStart += 1
							}
						}
						let start = wrcStart + (wrcStartChar == 0 ? 0 : 1)
						var end = wrcEnd - (wrcStartChar == 0 ? 0 : 1)
						if ch[at: end] == "。" { end -= 1 }
						var blength = 0
						var hasBr = false
						var inChuki = false
						var inRuby = false
						var i = start
						while i < end {
							if inChuki {
								if ch[i] == "］" { inChuki = false }
							} else if i < end - 1 && ch[i] == "［" && ch[i + 1] == "＃" {
								if i < end - 4 && ch[i + 2] == "改" && ch[i + 3] == "行" && ch[i + 4] == "］" { hasBr = true; break }
								inChuki = true
								i += 1
							} else if inRuby {
								if ch[i] == "》" { inRuby = false }
							} else if i < end - 1 && ch[i] == "《" {
								inRuby = true
							} else {
								blength += CharUtils.isHalf(ch[i]) ? 1 : 2
							}
							i += 1
						}
						if !hasBr {
							let half = Int(ceil(Double(blength) / 2.0))
							blength = 0
							inChuki = false
							inRuby = false
							i = start
							while i < end {
								if inChuki {
									if ch[i] == "］" { inChuki = false }
								} else if i < end - 1 && ch[i] == "［" && ch[i + 1] == "＃" {
									inChuki = true
									i += 1
								} else if inRuby {
									if ch[i] == "》" { inRuby = false }
								} else if i < end - 1 && ch[i] == "《" {
									inRuby = true
								} else {
									if blength >= half { wrcBrPos = i; break }
									blength += CharUtils.isHalf(ch[i]) ? 1 : 2
								}
								i += 1
							}
							// Java precedence quirk: (a && b && c) || d
							if wrcBrPos > 0 && wrcBrPos < ch.count && ch[wrcBrPos] == "、" || ch[at: wrcBrPos] == "。" { wrcBrPos += 1 }
						}
					}
				} else if chukiName.endsWith("キャプション終わり") {
					if inImageTag {
						buf.append(t.tag("画像終わり"))
						buf.append("\n")
						inImageTag = false
						noBr = true
					}
				}
				if !noTagAppend {
					buf.append(tags[0])
					if tags.count > 1 { bufSuf.insert(0, tags[1]) }
				}
				if t.flagNoBr.contains(chukiName) { noBr = true }

			} else {
				let imageStartIdx = chukiTag.lastIndexOf("（")
				if imageStartIdx > -1 {
					if imageStartIdx == 2 && chukiTag.endsWith("）］") && chukiTag.indexOf(".", 2) == -1 {
						buf.append(t.tag("行右小書き"))
						buf.append(chukiTag.jsub(3, chukiTag.jlen - 2))
						buf.append(t.tag("行右小書き終わり"))
					} else if chukiTag.indexOf(".", 2) == -1 {
						log.info(lineNum, "注記未変換", chukiTag)
					} else if !noImage {
						if let rawPath = getImageChukiFileName(chukiTag, imageStartIdx) {
							let srcFilePath = rawPath.jtrim()
							if ch.count - 1 > chukiStart + chukiTag.jlen && ch[chukiStart + chukiTag.jlen] == "《" {
								var hasRubyStart = false
								var i = chukiStart - 1
								while i >= 0 {
									if ch[i] == "｜" { hasRubyStart = true; break }
									else if ch[i] == "》" { break }
									i -= 1
								}
								if !hasRubyStart {
									if !chukiTag.endsWith("#GAIJI#］") { log.info(lineNum, "画像にルビ", srcFilePath) }
									buf.append("｜")
								}
							}
							if chukiTag.endsWith("#GAIJI#］") {
								if let imgFileName = writer.getImageFilePath(srcFilePath, lineNum) {
									buf.append(javaFormat(t.tag("外字画像"), imgFileName))
									log.info(lineNum, "外字画像利用", srcFilePath)
								}
							} else if noIllust && !writer.isCoverImage {
								log.info(lineNum, "挿絵除外", chukiTag)
							} else if let dstFileName = writer.getImageFilePath(srcFilePath, lineNum) {
								if bookInfo.isImageSectionLine(lineNum) { noBr = true }
								if printImageChuki(out, buf, srcFilePath, dstFileName, hasImageCaption(chukiTag), lineNum) { noBr = true }
							}
						} else {
							log.error(lineNum, "注記エラー", chukiTag)
						}
					}
				} else if lowerChukiTag.startsWith("<img") {
					if noIllust && !writer.isCoverImage {
						log.info(lineNum, "挿絵除外", chukiTag)
					} else if !noImage {
						if let srcFilePath = getTagAttr(chukiTag, "src") {
							if let dstFileName = writer.getImageFilePath(srcFilePath.jtrim(), lineNum) {
								if bookInfo.isImageSectionLine(lineNum) { noBr = true }
								if printImageChuki(out, buf, srcFilePath, dstFileName, hasImageCaption(chukiTag), lineNum) { noBr = true }
							}
						} else {
							log.error(lineNum, "画像注記エラー", chukiTag)
						}
					}
				} else if lowerChukiTag.startsWith("<a") {
					if linkStarted { buf.append("</a>") }
					if let href = getTagAttr(chukiTag, "href"), href.startsWith("http") {
						buf.append(chukiTag.replaceAll("&", "&amp;"))
						linkStarted = true
					} else {
						linkStarted = false
					}
				} else if lowerChukiTag.jequals("</a>") {
					if linkStarted { buf.append(chukiTag) }
				} else {
					var patternMatched = false
					let m2 = JPattern.compile(Self.chukiPatternMap["折り返し"]!).matcher(chukiTag)
					if m2.find() {
						if inJisage >= 0 {
							log.warn(inJisage, "字下げ注記省略")
							buf.append(t.tag("字下げ省略"))
						}
						inJisage = lineNum
						let arg0 = Int(CharUtils.fullToHalf(m2.group(1) ?? "")) ?? 0
						let arg1 = Int(CharUtils.fullToHalf(m2.group(2) ?? "")) ?? 0
						buf.append(t.tag("折り返し1") + String(arg1))
						buf.append(t.tag("折り返し2") + String(arg0 - arg1))
						buf.append(t.tag("折り返し3"))
						noBr = true
						patternMatched = true
					}
					if !patternMatched {
						let m3 = JPattern.compile(Self.chukiPatternMap["字下げ字詰め"]!).matcher(chukiTag)
						if m3.find() {
							if inJisage >= 0 {
								log.warn(inJisage, "字下げ注記省略")
								buf.append(t.tag("字下げ省略"))
							}
							inJisage = lineNum
							let arg0 = Int(CharUtils.fullToHalf(m3.group(1) ?? "")) ?? 0
							let arg1 = Int(CharUtils.fullToHalf(m3.group(2) ?? "")) ?? 0
							buf.append(t.tag("字下げ字詰め1") + String(arg0))
							buf.append(t.tag("字下げ字詰め2") + String(arg1))
							buf.append(t.tag("字下げ字詰め3"))
							noBr = true
							patternMatched = true
						}
					}
					if !patternMatched {
						let m4 = JPattern.compile(Self.chukiPatternMap["字下げ複合"]!).matcher(chukiTag)
						if m4.find() {
							if inJisage >= 0 {
								log.warn(inJisage, "字下げ注記省略")
								buf.append(t.tag("字下げ省略"))
							}
							inJisage = lineNum
							let arg0 = Int(CharUtils.fullToHalf(m4.group(1) ?? "")) ?? 0
							buf.append(t.tag("字下げ複合1") + String(arg0))
							if chukiTag.indexOf("破線罫囲み") > 0 { buf.append(" ").append(t.tag("字下げ破線罫囲み")) }
							else if chukiTag.indexOf("罫囲み") > 0 { buf.append(" ").append(t.tag("字下げ罫囲み")) }
							if chukiTag.indexOf("破線枠囲み") > 0 { buf.append(" ").append(t.tag("字下げ破線枠囲み")) }
							else if chukiTag.indexOf("枠囲み") > 0 { buf.append(" ").append(t.tag("字下げ枠囲み")) }
							if chukiTag.indexOf("中央揃え") > 0 { buf.append(" ").append(t.tag("字下げ中央揃え")) }
							if chukiTag.indexOf("横書き") > 0 { buf.append(" ").append(t.tag("字下げ横書き")) }
							buf.append(t.tag("字下げ複合2"))
							noBr = true
							patternMatched = true
						}
					}
					if !patternMatched {
						let m5 = JPattern.compile(Self.chukiPatternMap["字下げ終わり複合"]!).matcher(chukiTag)
						if m5.find() {
							if inJisage == -1 { log.error(lineNum, "字下げ注記エラー") }
							else { buf.append(t.tag("ここで字下げ終わり")) }
							inJisage = -1
							noBr = true
							patternMatched = true
						}
					}
					if !patternMatched {
						if chukiTag.indexOf("底本では") == -1 && chukiTag.indexOf("に「ママ」") == -1 && chukiTag.indexOf("」はママ") == -1 {
							log.info(lineNum, "注記未変換", chukiTag)
						}
					}
				}
			}
			charStart = chukiStart + chukiTag.jlen
		}
		if charStart < ch.count { convertEscapedText(buf, &ch, charStart, ch.count) }
		if bufSuf.length > 0 { buf.append(bufSuf) }

		if separateColophon {
			if sectionCharLength > 0 && buf.length > 2 && buf.charAt(0) == "底" && buf.charAt(1) == "本" && buf.charAt(2) == "：" {
				if inJisage >= 0 { log.error(inJisage, "字下げ注記エラー") }
				else { setPageBreakTrigger(pageBreakNoChapter) }
			}
		}
		printLineBuffer(out, convertRubyText(buf.toString()), lineNum, noBr || inImageTag)
	}

	/// Writes an image tag; returns true if the image got its own page.
	private func printImageChuki(_ out: EpubWriter?, _ buf: JBuilder, _ srcFileName: String, _ dstFileName: String, _ hasCaption: Bool, _ lineNum: Int) -> Bool {
		let imagePageType = writer.getImagePageType(srcFileName, tagLevel, lineNum, hasCaption)
		let ratio = writer.getImageWidthRatio(srcFileName, hasCaption)
		func fmt(_ key: String) -> String { javaFormat(t.tag(key), dstFileName) }
		func fmtR(_ key: String) -> String { javaFormat(t.tag(key), ratio, dstFileName) }

		switch imagePageType {
		case PageBreakType.imageInlineW: buf.append(ratio <= 0 ? fmt("画像横") : fmtR("画像幅"))
		case PageBreakType.imageInlineH: buf.append(ratio <= 0 ? fmt("画像縦") : fmtR("画像幅"))
		case PageBreakType.imageInlineTopW: buf.append(ratio <= 0 ? fmt("画像上横") : fmtR("画像幅上"))
		case PageBreakType.imageInlineBottomW: buf.append(ratio <= 0 ? fmt("画像下横") : fmtR("画像幅下"))
		case PageBreakType.imageInlineTop: buf.append(ratio <= 0 ? fmt("画像上") : fmtR("画像幅上"))
		case PageBreakType.imageInlineBottom: buf.append(ratio <= 0 ? fmt("画像下") : fmtR("画像幅下"))
		case PageBreakType.imagePageNone:
			if ratio != -1 && imageFloatBlock {
				buf.append(ratio <= 0 ? fmt("画像浮") : fmtR("画像幅浮"))
			} else {
				buf.append(ratio <= 0 ? fmt("画像") : fmtR("画像幅"))
			}
		default:
			if ratio != -1 && imageFloatPage {
				if imagePageType == PageBreakType.imagePageW { buf.append(fmt("画像単横浮")) }
				else if imagePageType == PageBreakType.imagePageH { buf.append(fmt("画像単縦浮")) }
				else { buf.append(ratio <= 0 ? fmt("画像単浮") : fmtR("画像単幅浮")) }
			} else {
				if buf.length > 0 { printLineBuffer(out, buf, lineNum, true) }
				buf.append(fmt("画像"))
				buf.append(t.tag("画像終わり"))
				printImagePage(out, buf, lineNum, srcFileName, dstFileName, imagePageType)
				return true
			}
		}
		if hasCaption {
			inImageTag = true
			nextLineIsCaption = true
		} else {
			buf.append(t.tag("画像終わり"))
		}
		return false
	}

	/// Escapes &<> and normalizes doubled brackets before ruby conversion.
	private func convertEscapedText(_ buf: JBuilder, _ ch: inout [JChar], _ beginIn: Int, _ end: Int) {
		var begin = beginIn
		guard begin < ch.count else { return }
		switch ch[begin] {
		case 0xDB40:
			begin += 2
			log.warn(lineNum, "先頭にあるIVSを除去します")
		case 0xFE00...0xFE0F:
			begin += 1
			log.warn(lineNum, "先頭にあるIVSを除去します")
		default:
			break
		}
		var i = begin + 1
		while i < end {
			switch ch[i] {
			case "<":
				if ch[i - 1] == "<" && (i == begin + 1 || ch[i - 2] != "<") && (end - 1 == i || ch[i + 1] != "<") { ch[i - 1] = "※"; ch[i] = "《" }
			case ">":
				if ch[i - 1] == ">" && (i == begin + 1 || ch[i - 2] != ">") && (end - 1 == i || ch[i + 1] != ">") { ch[i - 1] = "※"; ch[i] = "》" }
			case "＜":
				if ch[i - 1] == "＜" && (i == begin + 1 || ch[i - 2] != "＜") && (end - 1 == i || ch[i + 1] != "＜") { ch[i - 1] = "※"; ch[i] = "《" }
			case "＞":
				if ch[i - 1] == "＞" && (i == begin + 1 || ch[i - 2] != "＞") && (end - 1 == i || ch[i + 1] != "＞") { ch[i - 1] = "※"; ch[i] = "》" }
			case "\u{3099}": ch[i] = "゛"
			case "\u{309A}": ch[i] = "゜"
			default: break
			}
			i += 1
		}
		var idx = begin
		while idx < end {
			switch ch[idx] {
			case 0: break
			case "&": buf.append("&amp;")
			case "<": buf.append("&lt;")
			case ">": buf.append("&gt;")
			default: buf.appendChar(ch[idx])
			}
			idx += 1
		}
	}

	// MARK: - Ruby

	/// Converts ｜漢字《かんじ》 ruby to <ruby> tags and applies tate-chu-yoko.
	func convertRubyText(_ line: String) -> JBuilder {
		let buf = JBuilder()
		var ch = line.jchars
		let end = ch.count
		var rubyStart = -1
		var rubyTopStart = -1
		var inRuby = false
		var rubyCharType = RubyCharType.null
		let rubyStartChuki = t.tag("ルビ開始")
		let rubyEndChuki = t.tag("ルビ終了")
		var noTcy = false

		var i = 0
		while i < end {
			if !noTcy && noTcyStart.contains(i) { noTcy = true }
			else if noTcy && noTcyEnd.contains(i) { noTcy = false }

			switch ch[i] {
			case "｜":
				if !CharUtils.isEscapedChar(ch, i) {
					if rubyStart != -1 { convertTcyText(buf, &ch, rubyStart, i, noTcy) }
					rubyStart = i + 1
					inRuby = true
				}
			case "《":
				if !CharUtils.isEscapedChar(ch, i) {
					inRuby = true
					rubyTopStart = i
				}
			default: break
			}

			if inRuby {
				if ch[i] == "》" && !CharUtils.isEscapedChar(ch, i) {
					if rubyStart != -1 && rubyTopStart != -1 {
						do { // (Java's always-false noRuby branch removed)
							if rubyTopStart - rubyStart >= 30 {
								if line.jsub(rubyStart, rubyTopStart).replaceAll("<[^>]+>", " ").jlen >= 30 { log.warn(lineNum, "ルビが長すぎます") }
							}
							let endsWithRubyEnd = buf.length >= rubyEndChuki.jlen && buf.indexOf(rubyEndChuki, buf.length - rubyEndChuki.jlen) != -1
							if rubyTopStart - rubyStart == i - rubyTopStart - 1 && CharUtils.isSameChars(ch, rubyTopStart + 1, i) {
								// same length and all the same character: one ruby per character
								if !endsWithRubyEnd { buf.append(rubyStartChuki) } else { buf.setLength(buf.length - rubyEndChuki.jlen) }
								for j in 0..<(rubyTopStart - rubyStart) {
									convertReplacedChar(buf, &ch, rubyStart + j, noTcy)
									buf.append(t.tag("ルビ前"))
									convertReplacedChar(buf, &ch, rubyTopStart + 1 + j, true)
									buf.append(t.tag("ルビ後"))
								}
								buf.append(rubyEndChuki)
							} else {
								if !endsWithRubyEnd { buf.append(rubyStartChuki) } else { buf.setLength(buf.length - rubyEndChuki.jlen) }
								convertTcyText(buf, &ch, rubyStart, rubyTopStart, noTcy)
								buf.append(t.tag("ルビ前"))
								convertTcyText(buf, &ch, rubyTopStart + 1, i, true)
								buf.append(t.tag("ルビ後"))
								buf.append(rubyEndChuki)
							}
						}
					}
					if rubyStart == -1 { log.warn(lineNum, "ルビ開始文字無し") }
					inRuby = false
					rubyStart = -1
					rubyTopStart = -1
				}
			} else {
				if rubyStart != -1 {
					var changed = false
					switch rubyCharType {
					case .alpha: if !CharUtils.isHalfSpace(ch[i]) || ch[i] == ">" { changed = true }
					case .fullAlpha: if !(CharUtils.isFullAlpha(ch[i]) || CharUtils.isFullNum(ch[i])) { changed = true }
					case .kanji: if !CharUtils.isKanji(ch, i) { changed = true }
					case .hiragana: if !CharUtils.isHiragana(ch[i]) { changed = true }
					case .katakana: if !CharUtils.isKatakana(ch[i]) { changed = true }
					case .null: break
					}
					if changed {
						convertTcyText(buf, &ch, rubyStart, i, noTcy)
						rubyStart = -1
						rubyCharType = .null
					}
				}
				if rubyStart == -1 {
					if CharUtils.isKanji(ch, i) { rubyStart = i; rubyCharType = .kanji }
					else if CharUtils.isHiragana(ch[i]) { rubyStart = i; rubyCharType = .hiragana }
					else if CharUtils.isKatakana(ch[i]) { rubyStart = i; rubyCharType = .katakana }
					else if CharUtils.isHalfSpace(ch[i]) && ch[i] != ">" { rubyStart = i; rubyCharType = .alpha }
					else if CharUtils.isFullAlpha(ch[i]) || CharUtils.isFullNum(ch[i]) { rubyStart = i; rubyCharType = .fullAlpha }
					else { convertReplacedChar(buf, &ch, i, noTcy); rubyCharType = .null }
				}
			}
			i += 1
		}
		if rubyStart != -1 { convertTcyText(buf, &ch, rubyStart, end, noTcy) }
		return buf
	}

	/// External entry for TOC labels.
	func convertTcyText(_ text: String) -> String {
		let buf = JBuilder()
		var ch = text.jchars
		convertTcyText(buf, &ch, 0, ch.count, false)
		return buf.toString()
	}

	private func printGlyphFontTag(_ buf: JBuilder, _ gaijiFileName: String, _ className: String, _ baseChar: JChar) -> Bool {
		let file = writer.gaijiFontDirectory.appendingPathComponent(gaijiFileName)
		var isDir: ObjCBool = false
		guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir), !isDir.boolValue else { return false }
		writer.addGaijiFont(className, file)
		buf.append("<span class=\"glyph ").append(className).append("\">").appendChar(baseChar).append("</span>")
		return true
	}

	private static func toCodePoint(_ hi: JChar, _ lo: JChar) -> Int {
		((Int(hi) - 0xD800) << 10) + (Int(lo) - 0xDC00) + 0x10000
	}

	private static func s(_ cs: JChar...) -> String { String(jchars: cs) }

	/// Tate-chu-yoko, IVS and glyph-font handling, then character output.
	private func convertTcyText(_ buf: JBuilder, _ ch: inout [JChar], _ begin: Int, _ end: Int, _ noTcy: Bool) {
		var i = begin
		while i < end {
			defer { i += 1 }
			if i < end - 1 && UTF16.isLeadSurrogate(ch[i]) {
				let code = Self.toCodePoint(ch[i], ch[i + 1])
				if i < end - 3 && ch[i + 2] == 0xDB40 {
					let ivsCode = hex(Self.toCodePoint(ch[i + 2], ch[i + 3]))
					if let ivs32FontMap {
						let className = "u" + hex(code) + "-u" + ivsCode
						if let f = ivs32FontMap[className], printGlyphFontTag(buf, f, className, "〓") {
							log.info(lineNum, "外字フォント利用(IVS含む)", Self.s(ch[i], ch[i + 1], ch[i + 2], ch[i + 3]) + "(" + f + ")")
							i += 3
							continue
						}
					}
					if let utf32FontMap, let f = utf32FontMap[code], printGlyphFontTag(buf, f, "u" + hex(code), "〓") {
						log.warn(lineNum, "外字フォント利用(IVS除外)", Self.s(ch[i], ch[i + 1]) + "(" + f + ") -" + ivsCode)
						i += 3
						continue
					}
					if printIvsSSP {
						if vertical { buf.append(t.tag("正立")) }
						buf.appendChar(ch[i]).appendChar(ch[i + 1]).appendChar(ch[i + 2]).appendChar(ch[i + 3])
						if vertical { buf.append(t.tag("正立終わり")) }
						log.info(lineNum, "拡張漢字＋IVSを出力します", Self.s(ch[i], ch[i + 1], ch[i + 2], ch[i + 3]) + "(u+" + hex(code) + "+" + ivsCode + ")")
					} else {
						buf.appendChar(ch[i]).appendChar(ch[i + 1])
						log.info(lineNum, "拡張漢字出力(IVS除外)", Self.s(ch[i], ch[i + 1]) + "(u+" + hex(code) + ") -" + ivsCode)
					}
					i += 3
					continue
				}
				if i < end - 2 && ch[i + 2] >= 0xFE00 && ch[i + 2] <= 0xFE0F {
					if let ivs32FontMap {
						let className = "u" + hex(code) + "-u" + hex(Int(ch[i + 2]))
						if let f = ivs32FontMap[className], printGlyphFontTag(buf, f, className, "〓") {
							log.info(lineNum, "外字フォント利用(IVS含む)", Self.s(ch[i], ch[i + 1], ch[i + 2]) + "(" + f + ")")
							i += 2
							continue
						}
					}
					if printIvsBMP {
						if vertical { buf.append(t.tag("正立")) }
						buf.appendChar(ch[i]).appendChar(ch[i + 1]).appendChar(ch[i + 2])
						if vertical { buf.append(t.tag("正立終わり")) }
						log.info(lineNum, "拡張漢字＋IVSを出力します", Self.s(ch[i], ch[i + 1], ch[i + 2]) + "(u+" + hex(code) + "+" + hex(Int(ch[i + 2])) + ")")
					} else {
						buf.appendChar(ch[i]).appendChar(ch[i + 1])
						log.info(lineNum, "拡張漢字出力(IVS除外)", Self.s(ch[i], ch[i + 1]) + "(u+" + hex(code) + ") -" + hex(Int(ch[i + 2])) + ")")
					}
					i += 2
					continue
				}
				if let utf32FontMap, let f = utf32FontMap[code], printGlyphFontTag(buf, f, "u" + hex(code), "〓") {
					log.info(lineNum, "外字フォント利用", Self.s(ch[i], ch[i + 1]) + "(" + f + ")")
					i += 1
					continue
				}
				buf.appendChar(ch[i]).appendChar(ch[i + 1])
				log.info(lineNum, "拡張漢字出力", Self.s(ch[i], ch[i + 1]) + "(u+" + hex(code) + ")")
				i += 1
				continue
			}

			if i < end - 2 && ch[i + 1] == 0xDB40 {
				let ivsCode = hex(Self.toCodePoint(ch[i + 1], ch[i + 2]))
				if let ivs16FontMap {
					let className = "u" + hex(Int(ch[i])) + "-u" + ivsCode
					if let f = ivs16FontMap[className], printGlyphFontTag(buf, f, className, "〓") {
						log.info(lineNum, "外字フォント利用(IVS含む)", Self.s(ch[i], ch[i + 1], ch[i + 2]) + "(" + f + ")")
						i += 2
						continue
					}
				}
				if let utf16FontMap, let f = utf16FontMap[Int(ch[i])], printGlyphFontTag(buf, f, "u" + hex(Int(ch[i])), "〓") {
					log.warn(lineNum, "外字フォント利用(IVS除外)", Self.s(ch[i]) + "(" + f + ") -" + ivsCode)
					i += 2
					continue
				}
				if printIvsSSP {
					if vertical { buf.append(t.tag("正立")) }
					buf.appendChar(ch[i]).appendChar(ch[i + 1]).appendChar(ch[i + 2])
					if vertical { buf.append(t.tag("正立終わり")) }
					log.info(lineNum, "IVSを出力します", Self.s(ch[i], ch[i + 1], ch[i + 2]) + "(u+" + hex(Int(ch[i])) + "+" + ivsCode + ")")
				} else {
					buf.appendChar(ch[i])
					log.info(lineNum, "IVS除外", Self.s(ch[i]) + "(u+" + hex(Int(ch[i])) + ") -" + ivsCode)
				}
				i += 2
				continue
			}
			if i < end - 1 && ch[i + 1] >= 0xFE00 && ch[i + 1] <= 0xFE0F {
				if let ivs32FontMap {
					let className = "u" + hex(Int(ch[i])) + "-u" + hex(Int(ch[i + 1]))
					if let f = ivs32FontMap[className], printGlyphFontTag(buf, f, className, "〓") {
						log.info(lineNum, "外字フォント利用(IVS含む)", Self.s(ch[i]) + "(" + f + ")")
						i += 1
						continue
					}
				}
				if let utf16FontMap, let f = utf16FontMap[Int(ch[i])], printGlyphFontTag(buf, f, "u" + hex(Int(ch[i])), "〓") {
					log.info(lineNum, "外字フォント利用(IVS除外)", Self.s(ch[i]) + "(" + f + ") -" + hex(Int(ch[i + 1])))
					i += 1
					continue
				}
				if printIvsBMP {
					buf.appendChar(ch[i]).appendChar(ch[i + 1])
					log.info(lineNum, "IVSを出力します", Self.s(ch[i], ch[i + 1]) + "(u+" + hex(Int(ch[i])) + "+" + hex(Int(ch[i + 1])) + ")")
				} else {
					buf.appendChar(ch[i])
					log.info(lineNum, "IVS除外", Self.s(ch[i]) + "(u+" + hex(Int(ch[i])) + ") -" + hex(Int(ch[i + 1])))
				}
				i += 1
				continue
			}

			if let utf16FontMap, let f = utf16FontMap[Int(ch[i])], printGlyphFontTag(buf, f, "u" + hex(Int(ch[i])), "〓") {
				log.info(lineNum, "外字フォント利用", Self.s(ch[i]) + "(" + f + ")")
				continue
			}

			if vertical && !(inYoko || noTcy) {
				if tcy(buf, ch, &i) { continue }
			}

			if vertical {
				if i + 1 < ch.count && (ch[i + 1] == "゛" || ch[i + 1] == "゜") {
					if CharUtils.isHiragana(ch[i]) || CharUtils.isKatakana(ch[i]) || ch[i] == "〻" {
						if ch[i + 1] == "゛" {
							if ch[i] != "ッ" && ("か" <= ch[i] && ch[i] <= "と" || "カ" <= ch[i] && ch[i] <= "ト") {
								ch[i] = ch[i] + 1
								buf.appendChar(ch[i])
								i += 1
								continue
							}
							let voiced: [JChar: JChar] = ["ウ": "ヴ", "ワ": "ヷ", "ヲ": "ヺ", "う": "ゔ", "ゝ": "ゞ", "ヽ": "ヾ"]
							if let v = voiced[ch[i]] { buf.appendChar(v); i += 1; continue }
						}
						if "は" <= ch[i] && ch[i] <= "ほ" || "ハ" <= ch[i] && ch[i] <= "ホ" {
							buf.appendChar(ch[i + 1] == "゛" ? ch[i] + 1 : ch[i] + 2)
							i += 1
							continue
						}
						if dakutenType == 1 && !(inYoko || noTcy) {
							buf.append("<span class=\"dakuten\">")
							buf.appendChar(ch[i])
							buf.append("<span>")
							buf.append(ch[i + 1] == "゛" ? "゛" : "゜")
							buf.append("</span></span>")
							i += 1
							continue
						} else if dakutenType == 2 {
							var className = "u" + hex(Int(ch[i]))
							className += ch[i + 1] == "゛" ? "-u3099" : "-u309a"
							if printGlyphFontTag(buf, "dakuten/" + className + ".ttf", className, ch[i]) {
								log.info(lineNum, "濁点フォント利用", Self.s(ch[i], ch[i + 1]))
								i += 1
								continue
							}
						}
					}
				}
			}
			convertReplacedChar(buf, &ch, i, noTcy)
		}
	}

	/// Automatic tate-chu-yoko for half-width digits and !? (vertical text).
	/// Returns true if it wrote output and advanced `i` past the run (minus the loop's own +1).
	private func tcy(_ buf: JBuilder, _ ch: [JChar], _ i: inout Int) -> Bool {
		func wrap(_ n: Int) {
			buf.append(t.tag("縦中横"))
			for k in 0..<n { buf.appendChar(ch[i + k]) }
			buf.append(t.tag("縦中横終わり"))
			i += n - 1
		}
		let c = ch[i]
		if CharUtils.isNum(c) {
			guard autoYoko else { return false }
			if autoYokoNum3 && i + 2 < ch.count && CharUtils.isNum(ch[i + 1]) && CharUtils.isNum(ch[i + 2]) {
				if !checkTcyPrev(ch, i - 1) || !checkTcyNext(ch, i + 3) { return false }
				wrap(3); return true
			} else if i + 1 < ch.count && CharUtils.isNum(ch[i + 1]) {
				if !checkTcyPrev(ch, i - 1) || !checkTcyNext(ch, i + 2) { return false }
				wrap(2); return true
			} else if autoYokoNum1 && (i == 0 || !CharUtils.isNum(ch[i - 1])) && (i + 1 == ch.count || !CharUtils.isNum(ch[i + 1])) {
				if !checkTcyPrev(ch, i - 1) || !checkTcyNext(ch, i + 1) { return false }
				wrap(1); return true
			}
			// 1月1日 / 1月10日
			if i + 3 < ch.count && ch[i + 1] == "月" && "0" <= ch[i + 2] && ch[i + 2] <= "9" &&
				(ch[i + 3] == "日" || (i + 4 < ch.count && "0" <= ch[i + 3] && ch[i + 3] <= "9" && ch[i + 4] == "日")) {
				wrap(1); return true
			}
			if i > 1 && i + 1 < ch.count && (ch[i - 1] == "年" && ch[i + 1] == "月" || ch[i - 1] == "月" && ch[i + 1] == "日" || ch[i - 1] == "第" && (ch[i + 1] == "刷" || ch[i + 1] == "版" || ch[i + 1] == "巻")) {
				wrap(1); return true
			}
			if i > 2 && (ch[i - 2] == "明" && ch[i - 1] == "治" || ch[i - 2] == "大" && ch[i - 1] == "正" || ch[i - 2] == "昭" && ch[i - 1] == "和" || ch[i - 2] == "平" && ch[i - 1] == "成") {
				wrap(1); return true
			}
			return false
		}
		if c == "!" || c == "?" {
			guard autoYoko else { return false }
			if autoYokoEQ3 && i + 2 < ch.count && (ch[i + 1] == "!" || ch[i + 1] == "?") && (ch[i + 2] == "!" || ch[i + 2] == "?") {
				if !checkTcyPrev(ch, i - 1) || !checkTcyNext(ch, i + 3) { return false }
				wrap(3); return true
			} else if i + 1 < ch.count && (ch[i + 1] == "!" || ch[i + 1] == "?") {
				if !checkTcyPrev(ch, i - 1) || !checkTcyNext(ch, i + 2) { return false }
				wrap(2); return true
			} else if autoYokoEQ1 && (i == 0 || !CharUtils.isNum(ch[i - 1])) && (i + 1 == ch.count || !CharUtils.isNum(ch[i + 1])) {
				if !checkTcyPrev(ch, i - 1) || !checkTcyNext(ch, i + 1) { return false }
				wrap(1); return true
			}
		}
		return false
	}

	/// The character before a tcy run must not be half-width (tags and spaces skipped).
	func checkTcyPrev(_ ch: [JChar], _ iIn: Int) -> Bool {
		var i = iIn
		while i >= 0 {
			if ch[i] == ">" {
				repeat { i -= 1 } while i >= 0 && ch[i] != "<"
				i -= 1
				continue
			}
			if ch[i] == " " { i -= 1; continue }
			return !CharUtils.isHalf(ch[i])
		}
		return true
	}

	/// The character after a tcy run must not be half-width (tags and spaces skipped).
	func checkTcyNext(_ ch: [JChar], _ iIn: Int) -> Bool {
		var i = iIn
		while i < ch.count {
			if ch[i] == "<" {
				repeat { i += 1 } while i < ch.count && ch[i] != ">"
				i += 1
				continue
			}
			if ch[i] == " " { i += 1; continue }
			return !CharUtils.isHalf(ch[i])
		}
		return true
	}

	private static let uprightChars: Set<JChar> = Set(("÷±∞∴∵ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩⅪⅫⅰⅱⅲⅳⅴⅵⅶⅷⅸⅹⅺⅻ⓪①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳"
		+ "㉑㉒㉓㉔㉕㉖㉗㉘㉙㉚㉛㉜㉝㉞㉟㊱㊲㊳㊴㊵㊶㊷㊸㊹㊺㊻㊼㊽㊾㊿△▽▲▼☆★♂♀♪♭§†‡‼⁇⁉⁈©®⁑⁂"
		+ "◐◑◒◓▷▶◁◀♤♠♢♦♡♥♧♣❤☖☗☎☁☂☃♨▱⊿✿☹☺☻✓✔␣⏎♩♮♫♬ℓ№℡ℵℏ℧").utf16)

	/// Writes one character: escapes, replace.txt, space handling, vertical substitutions.
	private func convertReplacedChar(_ buf: JBuilder, _ ch: inout [JChar], _ idx: Int, _ noTcy: Bool) {
		if ch[idx] == 0 { return }
		let length = buf.length
		var escaped = false
		if idx > 0 {
			switch ch[idx] {
			case "》", "《", "｜", "＃", "※":
				if ch[idx - 1] == "※" {
					buf.setLength(length - 1)
					escaped = true
				}
			default: break
			}
		}
		if let replaceMap, let replaced = replaceMap[ch[idx]] {
			buf.append(replaced)
			return
		}
		if idx > 1 || (idx == 1 && !escaped) {
			if let replace2Map, let replaced = replace2Map[Self.s(ch[idx - (escaped ? 2 : 1)], ch[idx])] {
				buf.setLength(length - 1)
				buf.append(replaced)
				return
			}
		}
		if escaped {
			buf.appendChar(ch[idx])
			ch[idx] = "　" // ※※ のための対策
			return
		}
		if !(inYoko || noTcy) {
			if spaceHyphenation == 1 || spaceHyphenation == 2 {
				if idx > 20 && ch[idx] == "　" && buf.length > 0 && buf.charAt(buf.length - 1) != "　" && (idx - 1 == ch.count || idx + 1 < ch.count && ch[idx + 1] != "　") {
					if spaceHyphenation == 1 { buf.append("<span class=\"fullsp\"> </span>") }
					else { buf.appendChar(0x2000).appendChar(0x2000) }
					return
				}
			}
		}
		if vertical && !inYoko {
			switch ch[idx] {
			case "≪": buf.append("《")
			case "≫": buf.append("》")
			case "“": buf.append("〝")
			case "”": buf.append("〟")
			case "―": buf.append("─")
			default:
				if Self.uprightChars.contains(ch[idx]) && !noTcy {
					buf.append(t.tag("正立"))
					buf.appendChar(ch[idx])
					buf.append(t.tag("正立終わり"))
				} else {
					buf.appendChar(ch[idx])
				}
			}
		} else {
			switch ch[idx] {
			case "≪": buf.append("《")
			case "≫": buf.append("》")
			case "―": buf.append("─")
			default: buf.appendChar(ch[idx])
			}
		}
	}

	// MARK: - Output

	private func printImagePage(_ out: EpubWriter?, _ buf: JBuilder, _ lineNum: Int, _ srcFileName: String, _ dstFileName: String, _ imagePageType: Int) {
		let hasPageBreakTrigger = pageBreakTrigger != nil && !pageBreakTrigger!.noChapter
		let trigger: PageBreakType
		switch imagePageType {
		case PageBreakType.imagePageW: trigger = pageBreakImageW
		case PageBreakType.imagePageH: trigger = pageBreakImageH
		case PageBreakType.imagePageNoFit: trigger = pageBreakImageNoFit
		default: trigger = pageBreakImageAuto
		}
		setPageBreakTrigger(trigger)
		trigger.srcFileName = srcFileName
		trigger.dstFileName = dstFileName
		printLineBuffer(out, buf, lineNum, true)
		setPageBreakTrigger(hasPageBreakTrigger ? pageBreakNormal : pageBreakNoChapter)
	}

	/// Sets (or with nil, cancels) the pending page break.
	func setPageBreakTrigger(_ trigger: PageBreakType?) {
		printEmptyLines = 0
		pageBreakTrigger = trigger
		if let trigger, trigger.pageType != PageBreakType.pageNormal { skipMiddleEmpty = true }
	}

	/// Writes one converted line, handling pending page breaks, empty lines and TOC ids.
	func printLineBuffer(_ out: EpubWriter?, _ buf: JBuilder, _ lineNum: Int, _ noBr: Bool) {
		var line = buf.toString()
		var length = buf.length
		if CharUtils.isSpace(line) { line = ""; length = 0 }

		var idIdx = 1
		var chapterId: String? = nil
		if removeEmptyLine > 0 && length > 0 && CharUtils.isSpace(line) { line = ""; length = 0 }
		if length == 0 {
			if !skipMiddleEmpty && !noBr { printEmptyLines += 1 }
			buf.setLength(0)
			return
		}

		let chapterLineInfo = bookInfo.getChapterLineInfo(lineNum)

		var tagStart = 0
		var tagEnd = 0
		var inTag = false
		let lu = line.jchars
		for i in 0..<length {
			if inTag {
				if lu[i] == "/" && lu[at: i + 1] == ">" { tagEnd += 1 }
				if lu[i] == ">" { inTag = false }
			} else if lu[i] == "<" {
				if i < length - 1 && lu[i + 1] == "/" { tagEnd += 1 } else { tagStart += 1 }
				inTag = true
			}
		}

		if let out {
			if forcePageBreak && pageBreakTrigger == nil && tagLevel == 0 {
				if pageByteSize > forcePageBreakSize {
					setPageBreakTrigger(pageBreakNoChapter)
				} else if forcePageBreakEmptyLine > 0 && printEmptyLines >= forcePageBreakEmptyLine && pageByteSize > forcePageBreakEmptySize {
					setPageBreakTrigger(pageBreakNoChapter)
				} else if forcePageBreakChapterLevel > 0 && pageByteSize > forcePageBreakChapterSize {
					if chapterLineInfo != nil { setPageBreakTrigger(pageBreakNoChapter) }
					else if tagStart - tagEnd > 0 && bookInfo.getChapterLevel(lineNum + 1) > 0 { setPageBreakTrigger(pageBreakNoChapter) }
				}
			}

			if let trigger = pageBreakTrigger {
				if trigger.pageType != PageBreakType.pageNormal {
					writer.nextSection(lineNum, trigger.pageType, PageBreakType.imagePageNone, nil)
				} else {
					writer.nextSection(lineNum, PageBreakType.pageNormal, trigger.imagePageType, trigger.srcFileName)
				}
				pageByteSize = 0
				sectionCharLength = 0
				if tagLevel > 0 { log.error(lineNum, "タグが閉じていません") }
				tagLevel = 0
				lineIdNum = 0
				pageBreakTrigger = nil
			}

			skipMiddleEmpty = false
			if printEmptyLines > 0 {
				let br = t.tag("改行")
				var lines = min(maxEmptyLine, printEmptyLines - removeEmptyLine)
				if lastChapterLine >= lineNum - printEmptyLines - 2 { lines = max(1, lines) }
				var i = lines - 1
				while i >= 0 {
					out.write("<p>")
					out.write(br)
					out.write("</p>\n")
					i -= 1
				}
				pageByteSize += (br.jlen + 8) * lines
				printEmptyLines = 0
			}

			lineIdNum += 1
			if noBr {
				if chapterLineInfo != nil {
					let id = "kobo.\(lineIdNum).\(idIdx)"
					idIdx += 1
					chapterId = id
					if line.startsWith("<") {
						line = line.replaceFirst("(<[\\d|\\w]+)", "$1 id=\"" + id + "\"")
					} else {
						out.write("<span id=\"" + id + "\">" + String(jchars: [line.charAt(0)]) + "</span>")
						pageByteSize += id.jlen + 20
						line = line.jsub(1)
					}
				}
			} else {
				if withMarkId || (chapterLineInfo != nil && !chapterLineInfo!.pageBreakChapter) {
					let id = "kobo.\(lineIdNum).\(idIdx)"
					idIdx += 1
					chapterId = id
					out.write("<p id=\"" + id + "\">")
					pageByteSize += id.jlen + 14
				} else {
					out.write("<p>")
					pageByteSize += 7
				}
			}
			out.write(line)
			if forcePageBreak { pageByteSize += line.utf8.count }
			if !noBr { out.write("</p>\n") }

			if let info = chapterLineInfo, lastChapterLine != lineNum {
				if let name = info.chapterName, name.jlen > 0 {
					writer.addChapter(info.pageBreakChapter ? nil : chapterId, name, info.level % 10)
					lastChapterLine = lineNum
				}
			}
			sectionCharLength += length
		}
		tagLevel += tagStart - tagEnd
		buf.setLength(0)
	}
}

enum RubyCharType { case null, kanji, alpha, fullAlpha, hiragana, katakana }
