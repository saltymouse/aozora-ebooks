import Foundation

/// Text encodings the converter reads (the Java app offered MS932 and UTF-8).
public enum TextEncoding: String, Codable, CaseIterable, Sendable {
	case shiftJIS = "MS932"
	case utf8 = "UTF-8"

}

/// Java's MS932 (Windows-31J) decoder, table-driven so bytes decode exactly as in
/// AozoraEpub3. Apple's CP932 converter maps some codes Java leaves undefined.
final class MS932Decoder: Sendable {
	private let single: [Int32]
	private let double: [Int32]
	private let isLead: [Bool]

	static let shared = MS932Decoder()

	private init() {
		var single = [Int32](repeating: -1, count: 256)
		var double = [Int32](repeating: -1, count: 65536)
		var isLead = [Bool](repeating: false, count: 256)
		let text = (try? String(contentsOf: AozoraResources.file("ms932.tsv"), encoding: .utf8)) ?? ""
		for line in text.split(separator: "\n") where !line.hasPrefix("#") {
			let parts = line.split(separator: "\t")
			guard parts.count == 2, let cp = Int32(parts[1], radix: 16) else { continue }
			let key = parts[0]
			if key.hasPrefix("S"), let b = Int(key.dropFirst(), radix: 16) {
				single[b] = cp
			} else if key.hasPrefix("D"), let w = Int(key.dropFirst(), radix: 16) {
				double[w] = cp
				isLead[w >> 8] = true
			}
		}
		self.single = single
		self.double = double
		self.isLead = isLead
	}

	func decode(_ data: Data) -> String {
		var out = [UInt16]()
		out.reserveCapacity(data.count)
		data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
			let bytes = raw.bindMemory(to: UInt8.self)
			var i = 0
			let n = bytes.count
			while i < n {
				let b1 = Int(bytes[i])
				if single[b1] >= 0 {
					out.append(UInt16(single[b1])); i += 1
				} else if isLead[b1] {
					guard i + 1 < n else { out.append(0xFFFD); i += 1; continue }
					let b2 = Int(bytes[i + 1])
					let c = double[b1 << 8 | b2]
					if c >= 0 {
						out.append(UInt16(c)); i += 2
					} else if isLead[b2] || single[b2] >= 0 {
						out.append(0xFFFD); i += 1 // malformed(1): b2 starts the next character
					} else {
						out.append(0xFFFD); i += 2 // unmappable(2)
					}
				} else {
					out.append(0xFFFD); i += 1
				}
			}
		}
		return String(decoding: out, as: UTF16.self)
	}
}

enum TextIO {
	/// Decodes like Java's InputStreamReader: invalid sequences become U+FFFD instead of failing.
	static func decode(_ data: Data, _ encoding: TextEncoding) -> String {
		switch encoding {
		case .utf8: return String(decoding: data, as: UTF8.self)
		case .shiftJIS: return MS932Decoder.shared.decode(data)
		}
	}

	/// Splits into lines like `BufferedReader.readLine`: \n, \r and \r\n end a line,
	/// and a trailing terminator does not produce an extra empty line.
	static func lines(_ text: String) -> [String] {
		var out: [String] = []
		var cur: [JChar] = []
		var prevCR = false
		for c in text.utf16 {
			if c == 0x0A {
				if prevCR { prevCR = false; continue }
				out.append(String(jchars: cur)); cur.removeAll(keepingCapacity: true)
			} else if c == 0x0D {
				out.append(String(jchars: cur)); cur.removeAll(keepingCapacity: true)
				prevCR = true
				continue
			} else {
				cur.append(c)
			}
			prevCR = false
		}
		if !cur.isEmpty { out.append(String(jchars: cur)) }
		return out
	}

	static func lines(_ data: Data, _ encoding: TextEncoding) -> [String] {
		lines(decode(data, encoding))
	}

	/// Reads a UTF-8 resource file into lines.
	static func readLines(_ url: URL) throws -> [String] {
		lines(try Data(contentsOf: url), .utf8)
	}
}

/// Locates the bundled data files (templates, chuki tables, presets, web definitions).
public enum AozoraResources {
	public static var root: URL {
		Bundle.module.resourceURL!.appendingPathComponent("Resources", isDirectory: true)
	}
	public static var templateDirectory: URL { root.appendingPathComponent("template", isDirectory: true) }
	public static var presetsDirectory: URL { root.appendingPathComponent("presets", isDirectory: true) }
	public static var webDirectory: URL { root.appendingPathComponent("web", isDirectory: true) }
	public static var gaijiDirectory: URL { root.appendingPathComponent("gaiji", isDirectory: true) }
	static func file(_ name: String) -> URL { root.appendingPathComponent(name) }
}
