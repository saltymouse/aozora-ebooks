import Foundation

/// The chuki (注記) tag tables from chuki_tag.txt and chuki_tag_suf.txt.
/// Loaded once and shared; the Java version kept these in static fields.
final class ChukiTables: Sendable {
	/// chuki name -> [replacement, (tag closed at end of line)]
	let chukiMap: [String: [String]]
	let flagNoBr: Set<String>
	let flagNoRubyStart: Set<String>
	let flagNoRubyEnd: Set<String>
	let flagPageBreak: Set<String>
	let flagMiddle: Set<String>
	let flagBottom: Set<String>
	let kunten: Set<String>
	/// forward-reference chuki -> [open tag name, close tag name]
	let sufChukiMap: [String: [String]]

	static let shared = ChukiTables()

	private init() {
		var chukiMap: [String: [String]] = [:]
		var noBr = Set<String>(), rubyStart = Set<String>(), rubyEnd = Set<String>()
		var pageBreak = Set<String>(), middle = Set<String>(), bottom = Set<String>(), kunten = Set<String>()
		for line in (try? TextIO.readLines(AozoraResources.file("chuki_tag.txt"))) ?? [] {
			guard line.jlen > 0, line.charAt(0) != "#" else { continue }
			let values = line.split(regex: "\t")
			let tags: [String]
			if values.count == 1 { tags = [""] }
			else if values.count > 2 && values[2].jlen > 0 { tags = [values[1], values[2]] }
			else { tags = [values[1]] }
			chukiMap[values[0]] = tags
			if values.count > 3, let flag = values[3].utf16.first {
				switch flag {
				case "1": noBr.insert(values[0])
				case "2": rubyStart.insert(values[0])
				case "3": rubyEnd.insert(values[0])
				case "P": pageBreak.insert(values[0])
				case "M": pageBreak.insert(values[0]); middle.insert(values[0])
				case "K": kunten.insert(values[0])
				case "L": pageBreak.insert(values[0]); bottom.insert(values[0])
				default: break
				}
			}
		}
		var suf: [String: [String]] = [:]
		for line in (try? TextIO.readLines(AozoraResources.file("chuki_tag_suf.txt"))) ?? [] {
			guard line.jlen > 0, line.charAt(0) != "#" else { continue }
			let values = line.split(regex: "\t")
			guard values.count > 1 else { continue }
			let tags = values.count > 2 && values[2].jlen > 0 ? [values[1], values[2]] : [values[1]]
			suf[values[0]] = tags
			if values.count > 3 && values[3].jlen > 0 { suf[values[3] + values[0]] = tags }
		}
		self.chukiMap = chukiMap
		self.flagNoBr = noBr
		self.flagNoRubyStart = rubyStart
		self.flagNoRubyEnd = rubyEnd
		self.flagPageBreak = pageBreak
		self.flagMiddle = middle
		self.flagBottom = bottom
		self.kunten = kunten
		self.sufChukiMap = suf
	}

	/// First replacement string of a chuki (Java `chukiMap.get(name)[0]`).
	func tag(_ name: String) -> String { chukiMap[name]?[0] ?? "" }
}

/// 「基本ラテン文字のみによる拡張ラテン文字Aの分解表記」 -> Latin characters (port of `LatinConverter`).
final class LatinConverter: Sendable {
	private let latinMap: [String: JChar]

	static let shared = LatinConverter()

	private init() {
		var map: [String: JChar] = [:]
		for line in (try? TextIO.readLines(AozoraResources.file("chuki_latin.txt"))) ?? [] {
			guard line.jlen > 0, line.charAt(0) != "#" else { continue }
			let values = line.split(regex: "\t")
			guard values.count > 1, let ch = values[1].utf16.first else { continue }
			if values[0].jlen > 0 { map[values[0]] = ch }
		}
		latinMap = map
	}

	func toLatinString(_ separated: String) -> String {
		let ch = separated.jchars
		var out: [JChar] = []
		var i = 0
		while i < ch.count {
			if i < ch.count - 1 {
				if let latin = latinMap[String(jchars: ch[i..<i + 2])] { out.append(latin); i += 2; continue }
				if i < ch.count - 2, let latin = latinMap[String(jchars: ch[i..<i + 3])] { out.append(latin); i += 3; continue }
			}
			out.append(ch[i])
			i += 1
		}
		return String(jchars: out)
	}
}

/// Aozora gaiji notation -> Unicode or substitute text (port of `AozoraGaijiConverter` + `JisConverter`).
final class GaijiConverter: Sendable {
	private let chukiUtfMap: [String: String]
	private let chukiAltMap: [String: String]
	/// "men-ku-ten" -> characters
	private let jis: [String: String]

	static let shared = GaijiConverter()

	private init() {
		var utf: [String: String] = [:]
		GaijiConverter.load("chuki_ivs.txt", into: &utf)
		GaijiConverter.load("chuki_utf.txt", into: &utf)
		var alt: [String: String] = [:]
		GaijiConverter.load("chuki_alt.txt", into: &alt)
		chukiUtfMap = utf
		chukiAltMap = alt

		var jis: [String: String] = [:]
		for line in (try? TextIO.readLines(AozoraResources.file("jis_x0213.tsv"))) ?? [] {
			guard !line.hasPrefix("#") else { continue }
			let parts = line.split(regex: "\t")
			guard parts.count == 2 else { continue }
			var s = ""
			for h in parts[1].split(separator: " ") {
				if let v = UInt32(h, radix: 16), let u = Unicode.Scalar(v) { s.unicodeScalars.append(u) }
			}
			jis[parts[0]] = s
		}
		self.jis = jis
	}

	private static func load(_ name: String, into map: inout [String: String]) {
		for line in (try? TextIO.readLines(AozoraResources.file(name))) ?? [] {
			guard line.jlen > 0, line.charAt(0) != "#" else { continue }
			var charStart = line.indexOf("\t")
			if charStart == -1 { continue }
			charStart = line.indexOf("\t", charStart + 1)
			if charStart == -1 { continue }
			charStart += 1
			var chukiStart = line.indexOf("\t", charStart)
			if chukiStart == -1 { continue }
			chukiStart += 1
			if !line.startsWith("※［＃", chukiStart) { continue }
			var chukiEnd = line.indexOf("\t", chukiStart)
			var chukiCode = line.indexOf("、", chukiStart)
			if chukiCode != -1 && chukiCode + 1 < line.jlen && line.charAt(chukiCode + 1) == "「" { chukiCode = line.indexOf("、", chukiCode + 1) }
			if chukiCode != -1 && (chukiEnd == -1 || chukiCode < chukiEnd) { chukiEnd = chukiCode + 1 }
			if chukiEnd == -1 { chukiEnd = line.jlen }
			let utfChar = line.jsub(charStart, chukiStart - 1)
			let chuki = line.jsub(chukiStart + 3, chukiEnd - 1)
			if map[chuki] == nil { map[chuki] = utfChar }
		}
	}

	func toUtf(_ chuki: String) -> String? { chukiUtfMap[chuki] }
	func toAlterString(_ chuki: String) -> String? { chukiAltMap[chuki] }

	/// Code notation (U+XXXX, UCS-, unicode, or JIS men-ku-ten) to characters.
	func codeToCharString(_ code: String) -> String? {
		if code.startsWith("U+") || code.startsWith("u+") {
			let idx = code.indexOf("-")
			if idx == -1 {
				return GaijiConverter.char(Int(code.jsub(2), radix: 16))
			}
			var ivs = code.jsub(idx + 1)
			if ivs.startsWith("U+") || ivs.startsWith("u+") { ivs = ivs.jsub(2) }
			guard let base = GaijiConverter.char(Int(code.jsub(2, idx), radix: 16)),
			      let sel = GaijiConverter.char(Int(ivs, radix: 16)) else { return nil }
			return base + sel
		} else if code.startsWith("UCS-") {
			return GaijiConverter.char(Int(code.jsub(4), radix: 16))
		} else if code.startsWith("unicode") {
			return GaijiConverter.char(Int(code.jsub(7), radix: 16))
		}
		let codes: [String]
		if code.startsWith("第3水準") || code.startsWith("第4水準") {
			codes = code.jsub(4).split(regex: "-")
		} else {
			codes = code.split(regex: "-")
		}
		guard codes.count >= 3, let men = Int(codes[0]), let ku = Int(codes[1]), let ten = Int(codes[2]) else { return nil }
		return jis["\(men)-\(ku)-\(ten)"]
	}

	private static func char(_ code: Int?) -> String? {
		guard let code, code != 0, let u = Unicode.Scalar(UInt32(code)) else { return nil }
		return String(Character(u))
	}
}
