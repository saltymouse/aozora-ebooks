import Foundation
import Testing
@testable import AozoraKit

// Byte-for-byte parity with the Java app is covered by GoldenTests.
// These tests pin down the Java-compat helpers the port is built on.

@Suite struct JavaCompatTests {
	@Test func utf16Indexing() {
		let s = "𠮷野家の《ルビ》"
		#expect(s.jlen == 9)
		#expect(s.indexOf("《") == 5)
		#expect(s.jsub(2, 4) == "野家")
		#expect(s.lastIndexOf("家") == 3)
		#expect(s.charAt(0) == 0xD842)
		// out of range clamps instead of trapping
		#expect(s.jsub(7, 99) == "ビ》")
		#expect(s.charAt(99) == 0)
	}

	@Test func javaSplitDropsTrailingEmpties() {
		#expect("a\tb\t\t".split(regex: "\t") == ["a", "b"])
		#expect("".split(regex: "\t") == [""])
		#expect("a\t\tc".split(regex: "\t") == ["a", "", "c"])
	}

	@Test func regexHelpers() {
		#expect("［＃注記］本文".replaceAll("［＃.+?］", "") == "本文")
		#expect("  　題名　 ".replaceFirst("^[ |　]+", "") == "題名　 ")
		#expect("abc".matches("a.c"))
		#expect(!"abcd".matches("a.c"))
	}

	@Test func javaNumberFormatting() {
		#expect(javaString(1.8 as Float) == "1.8")
		#expect(javaString(100.0) == "100.0")
		#expect(javaString(56.25) == "56.25")
		#expect(javaFormat("width:%s%%", 56.25) == "width:56.25%")
	}

	@Test func nameUUIDMatchesJava() {
		// Java: UUID.nameUUIDFromBytes("人間失格-太宰治".getBytes())
		#expect(EpubWriter.nameUUID("人間失格-太宰治").count == 36)
		#expect(EpubWriter.nameUUID("a").hasPrefix("0cc175b9-c0f1-3"))
	}

	@Test func ms932DecodesLikeJava() {
		// 0x8160 is U+FF5E in MS932 (not U+301C as in JIS Shift_JIS)
		#expect(TextIO.decode(Data([0x81, 0x60]), .shiftJIS) == "\u{FF5E}")
		// lead byte followed by another lead byte: only one byte is replaced
		#expect(TextIO.decode(Data([0x87, 0xE5, 0xAD]), .shiftJIS) == "\u{FFFD}蟄")
	}

	@Test func readLineSemantics() {
		#expect(TextIO.lines("a\r\nb\rc\n") == ["a", "b", "c"])
		#expect(TextIO.lines("a\n\nb") == ["a", "", "b"])
	}
}

@Suite struct VelocityTests {
	final class Obj: VelocityObject {
		func vproperty(_ name: String) -> VValue {
			switch name {
			case "name": return .string("x")
			case "flag": return .bool(true)
			case "items": return .list([.int(1), .int(2), .int(3)])
			default: return .undefined
			}
		}
	}

	@Test func directivesGobbleTheirLine() throws {
		let t = try VelocityTemplate("a\r\n#if (${o.Flag})\r\nyes ${o.name}\r\n#else\r\nno\r\n#end\r\nb")
		let ctx = VelocityContext()
		ctx.put("o", Obj())
		#expect(t.render(ctx) == "a\r\nyes x\r\nb")
	}

	@Test func foreachBreakAndCount() throws {
		let t = try VelocityTemplate("#foreach($i in ${o.items})\n$velocityCount:$i\n#if ($velocityCount % 2 == 0)\n#break\n#end\n#end\n")
		let ctx = VelocityContext()
		ctx.put("o", Obj())
		#expect(t.render(ctx) == "1:1\n2:2\n")
	}

	@Test func undefinedReferencesEchoAndEmptyStringIsTrue() throws {
		let t = try VelocityTemplate("${missing}|#if (${e})E#end|#if (${missing})M#end")
		let ctx = VelocityContext()
		ctx.put("e", "")
		#expect(t.render(ctx) == "${missing}|E|")
	}

	@Test func setAndArithmetic() throws {
		let t = try VelocityTemplate("#set($idx=0)\n#set($idx=$idx+1)\n$idx ${s.length()} ${m[1]}")
		let ctx = VelocityContext()
		ctx.put("s", "あいう")
		ctx["m"] = .list([.string("a"), .string("b")])
		#expect(t.render(ctx) == "1 3 b")
	}
}

@Suite struct ImageTests {
	/// Java reads gray PNGs as linear TYPE_BYTE_GRAY; margins must match what it trims (342×473 output).
	@Test func grayscaleMarginDetection() throws {
		let url = ArchiveTests.fixtures.appendingPathComponent("gray_scan.png")
		let image = try #require(ImageUtils.decode(try Data(contentsOf: url)))
		let px = try #require(ImageUtils.Pixels(image))
		let m = ImageUtils.getPlainMargin(px, 0.15, 0.15, 0.8, 0.01, Int(Double(image.width) * 0.01), Int(Double(image.width) * 0.03), Int(Double(image.width) * 0.01), 0, 0.03)
		#expect(m == [7, 0, 8, 2])
	}
}

@Suite struct ArchiveTests {
	static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")

	@Test func readsRar5() throws {
		var names: [String] = []
		try ArchiveReader(url: Self.fixtures.appendingPathComponent("rar5_from_libarchive_tests.rar")).forEach { e, read in
			names.append(e.name)
			#expect(!read().isEmpty)
			return true
		}
		#expect(names == ["test1.bin", "test2.bin", "test3.bin", "test4.bin"])
	}

	@Test func decodesCP932ZipNames() throws {
		let names = try ArchiveReader(url: Self.fixtures.appendingPathComponent("[テスト] 画像zip.zip")).textEntryNames()
		#expect(names == ["book/test_image.txt"])
		var images: [String] = []
		try ArchiveReader(url: Self.fixtures.appendingPathComponent("[テスト] 画像zip.zip")).forEach { e, _ in
			images.append(e.name)
			return true
		}
		#expect(images.contains("book/img/縦長.png"))
	}

	@Test func convertsArchiveEndToEnd() throws {
		var settings = ConversionSettings()
		settings.confirm = false
		let out = FileManager.default.temporaryDirectory.appendingPathComponent("aozora-tests-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: out) }
		let engine = AozoraEpub(settings: settings)
		let books = try engine.prepare(Self.fixtures.appendingPathComponent("two_texts.zip"))
		#expect(books.count == 2)
		for book in books { try engine.convert(book, dstDirectory: out) }
		#expect(try FileManager.default.contentsOfDirectory(atPath: out.path).filter { $0.hasSuffix(".epub") }.count == 2)
	}
}
