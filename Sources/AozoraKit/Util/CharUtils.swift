import Foundation

/// Character classification and text helpers (port of `CharUtils`).
enum CharUtils {
	/// Full-width digits/letters to half-width.
	static func fullToHalf(_ src: String) -> String {
		var c = src.jchars
		for i in stride(from: c.count - 1, through: 0, by: -1) {
			if c[i] >= "０" && c[i] <= "９" { c[i] = c[i] - JChar(0xFF10) + JChar(0x30) }
			else if c[i] >= "Ａ" && c[i] <= "ｚ" { c[i] = c[i] &- JChar(0xFF41) &+ JChar(0x61) }
		}
		return String(jchars: c)
	}

	static func isSameChars(_ ch: [JChar], _ begin: Int, _ end: Int) -> Bool {
		var i = begin + 1
		while i < end {
			if ch[begin] != ch[i] { return false }
			i += 1
		}
		return true
	}

	static func isNum(_ ch: JChar) -> Bool { ch >= "0" && ch <= "9" }

	/// Latin incl. extended, excluding space.
	static func isHalf(_ ch: JChar) -> Bool { 0x21 <= ch && ch <= 0x02AF }
	static func isHalf(_ chars: [JChar]) -> Bool { chars.allSatisfy(isHalf) }

	/// Latin incl. extended and space.
	static func isHalfSpace(_ ch: JChar) -> Bool { 0x20 <= ch && ch <= 0x02AF }
	static func isHalfSpace(_ chars: [JChar]) -> Bool { chars.allSatisfy(isHalfSpace) }

	static func isFullAlpha(_ ch: JChar) -> Bool {
		("Ａ" <= ch && ch <= "Ｚ") || ("ａ" <= ch && ch <= "ｚ") || ("０" <= ch && ch <= "９") || ch == "＠" || ch == "＿"
	}
	static func isFullNum(_ ch: JChar) -> Bool { ch >= "０" && ch <= "９" }

	static func isHiragana(_ ch: JChar) -> Bool {
		("ぁ" <= ch && ch <= "ん") || ch == "ゕ" || ch == "ゖ" || ch == "ー" || ch == "ゝ" || ch == "ゞ" || ch == "ヽ" || ch == "ヾ" || ch == "゛" || ch == "゜"
			|| ch == "ι" // 濁点処理用の例外
	}

	static func isKatakana(_ ch: JChar) -> Bool {
		if "ァ" <= ch && ch <= "ヶ" { return true }
		switch ch {
		case "ァ", "ィ", "ゥ", "ェ", "ォ", "ヵ", "ㇰ", "ヶ", "ㇱ", "ㇲ", "ッ", "ㇳ", "ㇴ",
		     "ㇵ", "ㇶ", "ㇷ", "ㇸ", "ㇹ", "ㇺ", "ャ", "ュ", "ョ", "ㇻ", "ㇼ", "ㇽ", "ㇾ", "ㇿ", "ヮ",
		     "ー", "ゝ", "ゞ", "ヽ", "ヾ", "゛", "゜":
			return true
		default:
			return false
		}
	}

	/// All characters are half-width, full-width or en-quad (U+2000) spaces.
	static func isSpace(_ line: String) -> Bool {
		line.utf16.allSatisfy { $0 == " " || $0 == "　" || $0 == "\u{2000}" }
	}

	static func isAlpha(_ ch: JChar) -> Bool {
		("A" <= ch && ch <= "Z") || ("a" <= ch && ch <= "z") || (0x80 <= ch && ch <= 0x02AF)
	}

	/// Kanji check including surrogate pairs and IVS selectors.
	static func isKanji(_ ch: [JChar], _ i: Int) -> Bool {
		switch ch[i] {
		case "゛", "゜":
			// 二の字点は濁点付きも漢字
			return i > 0 && ch[i - 1] == "〻"
		default:
			return _isKanji(ch, i)
		}
	}

	private static func _isKanji(_ ch: [JChar], _ i: Int) -> Bool {
		let pre = i == 0 ? -1 : Int(ch[i - 1])
		let c = Int(ch[i])
		let suf = i + 1 >= ch.count ? -1 : Int(ch[i + 1])
		switch ch[i] {
		case "〓", "〆", "々", "〻": return true
		default: break
		}
		if 0x4E00 <= c && c <= 0x9FFF { return true }
		if 0xF900 <= c && c <= 0xFAFF { return true }
		if 0xFE00 <= c && c <= 0xFE0D { return true }
		if pre >= 0 {
			if pre == 0xDB40 && 0xDD00 <= c && c <= 0xDDEF { return true }
			if pre == 0xD87E && 0xDC00 <= c && c <= 0xDE1F { return true }
			let code = pre << 16 | c & 0xFFFF
			if 0xD840DC00 <= code && code <= 0xD869DEDF { return true }
			if 0xD869DF00 <= code && code <= 0xD86EDC1F { return true }
		}
		if suf >= 0 {
			if c == 0xDB40 && 0xDD00 <= suf && suf <= 0xDDEF { return true }
			if c == 0xD87E && 0xDC00 <= suf && suf <= 0xDE1F { return true }
			let code = c << 16 | suf & 0xFFFF
			if 0xD840DC00 <= code && code <= 0xD869DEDF { return true }
			if 0xD869DF00 <= code && code <= 0xD86EDC1F { return true }
		}
		return false
	}

	/// Replaces characters that can't appear in file names.
	static func escapeUrlToFile(_ str: String) -> String {
		str.replaceAll("(\\?|\\&)", "/").replaceAll("(:|\\*|\\||\\<|\\>|\"|\\\\)", "_")
	}

	/// Strips leading/trailing half- and full-width spaces (and `|`, as the Java regex does).
	static func removeSpace(_ text: String) -> String {
		text.replaceFirst("^[ |　]+", "").replaceFirst("[ |　]+$", "")
	}

	/// Removes chuki and HTML tags.
	static func removeTag(_ text: String) -> String {
		text.replaceAll("［＃.+?］", "").replaceAll("<[^>]+>", "")
	}

	/// Removes ruby markup, keeping escaped special characters.
	static func removeRuby(_ text: String) -> String {
		var buf: [JChar] = []
		let ch = text.jchars
		var inRuby = false
		for i in 0..<ch.count {
			if inRuby {
				if ch[i] == "》" && !isEscapedChar(ch, i) { inRuby = false }
			} else {
				switch ch[i] {
				case "｜":
					if isEscapedChar(ch, i) { buf.append(ch[i]) }
				case "《":
					if isEscapedChar(ch, i) { buf.append(ch[i]) } else { inRuby = true }
				default:
					buf.append(ch[i])
				}
			}
		}
		return String(jchars: buf)
	}

	/// True if the character at idx is escaped by an odd number of preceding ※.
	static func isEscapedChar(_ ch: [JChar], _ idx: Int) -> Bool {
		var escaped = false
		var i = idx - 1
		while i >= 0 {
			if ch[i] == "※" { escaped.toggle() } else { return escaped }
			i -= 1
		}
		return escaped
	}
	static func isEscapedChar(_ ch: JBuilder, _ idx: Int) -> Bool { isEscapedChar(ch.u, idx) }

	static func escapeHtml(_ text: String) -> String {
		text.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")
	}

	private static let chapterTagOpenPattern = "< *(img|a) [^>]*>"
	private static let chapterTagClosePattern = "< */ *(img|a)(>| [^>]*>)"

	/// Text for TOC and title use: chuki removed, escapes resolved, trimmed and truncated.
	static func getChapterName(_ line: String, _ maxLength: Int, _ reduce: Bool = true) -> String {
		var name = line.replaceAll("［＃.+?］", "")
			.replaceAll("※(※|《|》|［|］|〔|〕|〔|〕|〔|〕|｜)", "$1")
			.replaceAll("\t", " ").replaceFirst("^[ |　]+", "").replaceFirst("[ |　]+$", "")
		if reduce { name = name.replaceAll("(=|＝|-|―|─)+", "$1") }
		name = JPattern.compile(chapterTagOpenPattern, caseInsensitive: true).matcher(name).replaceAll("")
		name = JPattern.compile(chapterTagClosePattern, caseInsensitive: true).matcher(name).replaceAll("")
		if maxLength == 0 { return name }
		return name.jlen > maxLength ? name.jsub(0, maxLength) + "..." : name
	}

	static func removeBOM(_ str: String?) -> String? {
		guard let str, str.jlen > 0 else { return nil }
		return str.charAt(0) == 0xFEFF ? str.jsub(1) : str
	}
}
