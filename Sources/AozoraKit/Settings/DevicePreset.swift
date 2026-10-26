import Foundation

/// A device preset: screen size and the handful of settings a reader needs
/// (the Java app's "端末設定" menu, plus newer devices).
public struct DevicePreset: Identifiable, Hashable, Sendable {
	public var id: String { file }
	public let file: String
	public let name: String
	/// kindle, kobo, reader, books
	public let icon: String
	public let ini: [String: String]

	/// Presets shipped with AozoraEpub3 for 2013-era devices.
	public var isClassic: Bool { !["apple_books.ini", "kindle_send.ini", "kobo_clara.ini", "kobo_libra.ini"].contains(file) }

	public var ext: String { ini["Ext"] ?? ".epub" }

	/// What the preset produces, e.g. "EPUB" or "Kobo EPUB (.kepub.epub)".
	public var output: String { Self.describe(ext: ext) }

	public var needsKindlegen: Bool { ext.hasPrefix(".mobi") }

	public static func describe(ext: String) -> String {
		switch ext {
		case ".epub": return "EPUB"
		case ".kepub.epub": return String(localized: "Kobo EPUB (.kepub.epub)", bundle: .module)
		case ".fxl.kepub.epub": return String(localized: "Kobo fixed-layout EPUB", bundle: .module)
		case ".mobi": return "MOBI"
		case ".mobi+.epub": return "MOBI + EPUB"
		default: return ext
		}
	}

	public var screenSize: String {
		guard let w = ini["DispW"], let h = ini["DispH"] else { return "" }
		return "\(w)×\(h)"
	}

	public static func loadAll(_ dir: URL = AozoraResources.presetsDirectory) -> [DevicePreset] {
		let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
		let presets: [DevicePreset] = files.filter { $0.pathExtension == "ini" }.compactMap { url in
			guard let data = try? Data(contentsOf: url) else { return nil }
			let p = JavaProperties.parse(data)
			guard let name = p["PresetName"] else { return nil }
			let icon = (p["PresetIcon"] ?? "").replacingOccurrences(of: ".png", with: "")
			var ini = p
			ini["PresetName"] = nil
			ini["PresetIcon"] = nil
			return DevicePreset(file: url.lastPathComponent, name: name.trimmingCharacters(in: CharacterSet(charactersIn: "+ ")), icon: icon, ini: ini)
		}
		let order = ["apple_books.ini", "kindle_send.ini", "kobo_clara.ini", "kobo_libra.ini"]
		return presets.sorted { a, b in
			let ia = order.firstIndex(of: a.file) ?? 99, ib = order.firstIndex(of: b.file) ?? 99
			return ia != ib ? ia < ib : a.name < b.name
		}
	}
}
