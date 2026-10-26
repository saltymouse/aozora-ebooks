import CryptoKit
import Foundation
import ImageIO
import Testing
@testable import AozoraKit

/// Converts every fixture under several setting variants and compares each EPUB entry
/// (text by SHA-256, images by pixel size) with `Fixtures/golden/expected.json`.
///
/// The manifest was recorded when this port's output was byte-identical to the Java
/// AozoraEpub3 1.1.0b46 for all of these conversions, so a failure means output drifted
/// from the original. After an intentional change, re-record with
/// `AOZORA_UPDATE_GOLDEN=1 swift test --filter GoldenTests` and review the diff.
@Suite struct GoldenTests {
	static let fixtures = ArchiveTests.fixtures
	static let manifestURL = fixtures.appendingPathComponent("golden/expected.json")

	/// Setting variants (AozoraEpub3 .ini keys) layered on the defaults.
	static let configs: [String: [String: String]] = [
		"default": [:],
		"horizontal": ["Vertical": "", "TocPage": "1", "TocVertical": "", "TitlePage": "2"],
		"kobo": ["Ext": ".kepub.epub", "MarkId": "1", "SpaceHyphenation": "1", "PageBreakSize": "100",
		         "PageBreakEmpty": "1", "PageBreakChapter": "1", "NavNest": "1", "NcxNest": "1"],
		"titlenormal": ["TitlePage": "0", "CoverPage": "", "AutoYokoNum1": "1", "AutoYokoNum3": "1", "AutoYokoEQ1": "1",
		                "ChapterNumOnly": "1", "ChapterNumTitle": "1", "ChapterNumParen": "1", "ChapterNumParenTitle": "1",
		                "ChapterUseNextLine": "1", "ForceIndent": "1", "RemoveEmptyLine": "1", "MaxEmptyLine": "2"],
		"notitle": ["TitlePageWrite": "", "TitleType": "5", "CommentPrint": "1", "CommentConvert": "1", "ChukiRuby": "1",
		            "DakutenType": "2", "IvsBMP": "1", "IvsSSP": "1", "SameLineChapter": "1", "ChapterExclude": ""],
		"authorfirst": ["TitleType": "1", "PubFirst": "1", "ChukiRuby": "2", "DakutenType": "0", "ImageFloat": "1",
		                "ImageFloatPage": "1", "ImageFloatBlock": "1", "ImageScaleChecked": "", "UseFileName": "1",
		                "ChapterPattern": "1", "ChapterPatternText": "^(†|【|●|▼|■)"],
		"images": ["ResizeW": "1", "ResizeNumW": "800", "ResizeH": "1", "ResizeNumH": "900", "AutoMargin": "1",
		           "RotateImage": "1", "Gamma": "1", "GammaValue": "0.8", "JpegQuality": "70", "DispW": "758", "DispH": "1024",
		           "CoverW": "300", "CoverH": "400"],
		"images2": ["SvgImage": "1", "ImageSizeType": "1", "FitImage": "", "RotateImage": "2", "AutoMargin": "1",
		            "AutoMarginNombre": "3", "AutoMarginLimitH": "30", "AutoMarginLimitV": "30", "SinglePageWidth": "300"],
	]

	static var inputs: [URL] {
		let golden = fixtures.appendingPathComponent("golden")
		let texts = (try? FileManager.default.contentsOfDirectory(at: golden, includingPropertiesForKeys: nil)) ?? []
		return texts.filter { $0.pathExtension == "txt" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
			+ ["two_texts.zip", "[テスト] 画像zip.zip", "comic.cbz"].map { fixtures.appendingPathComponent($0) }
	}

	/// "config/input" → output file name → ordered [entry name, digest]
	typealias Manifest = [String: [String: [[String]]]]

	@Test func outputMatchesRecordedJavaParity() throws {
		var actual: Manifest = [:]
		for (name, overrides) in Self.configs {
			// same path as the CLI: defaults + overrides, written out and read back as a full .ini
			var s = ConversionSettings()
			s.apply(ini: overrides)
			var settings = ConversionSettings()
			settings.apply(ini: s.ini)
			settings.confirm = false
			for input in Self.inputs {
				actual["\(name)/\(input.lastPathComponent)"] = try convert(input, settings: settings)
			}
		}

		if ProcessInfo.processInfo.environment["AOZORA_UPDATE_GOLDEN"] == "1" {
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
			try encoder.encode(actual).write(to: Self.manifestURL)
			return
		}
		let expected = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: Self.manifestURL))
		#expect(Set(actual.keys) == Set(expected.keys))
		for key in actual.keys.sorted() {
			guard let want = expected[key], let got = actual[key] else { continue }
			#expect(got.keys.sorted() == want.keys.sorted(), "\(key): output files differ")
			for (file, entries) in got {
				guard let wantEntries = want[file] else { continue }
				let changed = zip(entries, wantEntries).filter { $0 != $1 }.map { $0.0[0] }
				#expect(changed.isEmpty && entries.count == wantEntries.count,
				        "\(key) \(file): changed \(changed), entries \(entries.count) vs \(wantEntries.count)")
			}
		}
	}

	private func convert(_ input: URL, settings: ConversionSettings) throws -> [String: [[String]]] {
		let out = FileManager.default.temporaryDirectory.appendingPathComponent("aozora-golden-\(UUID().uuidString)")
		try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: out) }
		let engine = AozoraEpub(settings: settings, log: Log())
		for book in try engine.prepare(input) { try engine.convert(book, dstDirectory: out) }

		var result: [String: [[String]]] = [:]
		for file in try FileManager.default.contentsOfDirectory(at: out, includingPropertiesForKeys: nil) {
			var entries: [[String]] = []
			try ArchiveReader(url: file).forEach { entry, read in
				entries.append([entry.name, Self.digest(entry.name, read())])
				return true
			}
			result[file.lastPathComponent.precomposedStringWithCanonicalMapping] = entries
		}
		return result
	}

	/// Images: pixel size (encoders differ from Java's). Fonts: byte count. Text: SHA-256 without the timestamp.
	static func digest(_ name: String, _ data: Data) -> String {
		if name.hasPrefix("OPS/images/") {
			guard let src = CGImageSourceCreateWithData(data as CFData, nil),
			      let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
			      let w = props[kCGImagePropertyPixelWidth], let h = props[kCGImagePropertyPixelHeight] else { return "image ?" }
			return "image \(w)x\(h)"
		}
		if name.hasSuffix(".ttf") || name.hasSuffix(".otf") { return "bytes \(data.count)" }
		let text = String(decoding: data, as: UTF8.self)
			.replacingOccurrences(of: #"<meta property="dcterms:modified">[^<]*</meta>"#, with: "", options: .regularExpression)
		return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
	}
}
