import Foundation
import CoreGraphics
import ImageIO

/// Tracks the images a book references, read from the file system or an archive
/// (port of `ImageInfoReader`).
public final class ImageInfoReader {
	/// Images live on disk next to the text (not inside an archive).
	let isFile: Bool
	let srcFile: URL
	/// Directory of the text file, ending in "/".
	let srcParentPath: String
	/// Parent path of the text entry inside the archive ("" at the root).
	var archiveTextParentPath = ""
	/// Image names in output order.
	private(set) var imageFileNames: [String] = []
	/// Archive: every image, loaded up front. File system: filled on demand.
	private var imageFileInfos: [String: ImageInfo] = [:]

	public init(isFile: Bool, srcFile: URL) {
		self.isFile = isFile
		self.srcFile = srcFile
		self.srcParentPath = srcFile.deletingLastPathComponent().path + "/"
	}

	/// Sets the parent path of the archive's text entry.
	func setArchiveTextEntry(_ entry: String) {
		let idx = entry.lastIndexOf("/")
		if idx > -1 { archiveTextParentPath = entry.jsub(0, idx + 1) }
	}

	func imageFile(_ fileName: String) -> URL { URL(fileURLWithPath: srcParentPath + fileName) }

	func addImageFileName(_ name: String) { imageFileNames.append(archiveTextParentPath + name) }

	func sortImageFileNames() { imageFileNames.sort { FileNameOrder.less($0, $1) } }

	func imageFileName(_ idx: Int) -> String { imageFileNames[idx] }

	public var countImageFileInfos: Int { imageFileInfos.count }
	public var countImageFileNames: Int { imageFileNames.count }

	func imageInfo(_ idx: Int) -> ImageInfo? {
		idx < imageFileNames.count ? imageInfo(imageFileNames[idx]) : nil
	}

	func imageInfo(_ srcImageFileName: String) -> ImageInfo? {
		if let info = imageFileInfos[srcImageFileName] { return info }
		if isFile {
			let url = URL(fileURLWithPath: srcParentPath + srcImageFileName)
			if FileManager.default.fileExists(atPath: url.path), let info = ImageInfo.read(url) {
				imageFileInfos[srcImageFileName] = info
				return info
			}
			return nil
		}
		return imageFileInfos[archiveTextParentPath + srcImageFileName]
	}

	/// Tries other extensions/cases when the referenced image doesn't exist.
	func correctExt(_ name: String) -> String? {
		if hasImage(name) { return name }
		for ext in ["png", "jpg", "jpeg", "gif", "PNG", "JPG", "JPEG", "GIF", "Png", "Jpg", "Jpeg", "Gif"] {
			let alt = name.replaceFirst("\\.\\w+$", "." + ext)
			if hasImage(alt) { return alt }
		}
		return nil
	}

	private func hasImage(_ name: String) -> Bool {
		if imageFileInfos[name] != nil { return true }
		if isFile { return FileManager.default.fileExists(atPath: srcParentPath + name) }
		return imageFileInfos[archiveTextParentPath + name] != nil
	}

	/// Reads the size of every image in an archive. With `addFileName`, also lists them in order.
	func loadArchiveImageInfos(_ srcFile: URL, addFileName: Bool, log: Log) throws {
		var idx = 0
		try ArchiveReader(url: srcFile).forEach { entry, read in
			defer { idx += 1 }
			guard !entry.isDirectory else { return true }
			let lower = entry.name.lowercased()
			guard lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".gif") else { return true }
			if let info = ImageInfo.read(read(), zipIndex: idx) {
				imageFileInfos[entry.name] = info
				if addFileName { addImageFileName(entry.name) }
			} else {
				log.error("画像が読み込めませんでした: \(entry.name)")
			}
			return true
		}
	}

	/// Adds archive images not referenced by the text, so they can be picked as the cover.
	func addNoNameImageFileName() {
		let existing = Set(imageFileNames)
		let names = imageFileInfos.keys.filter { !existing.contains($0) }.sorted { FileNameOrder.less($0, $1) }
		imageFileNames.append(contentsOf: names)
	}

	/// Raw bytes of an image by name (file system or archive).
	func imageData(_ srcImageFileName: String) -> Data? {
		if isFile {
			var name = srcImageFileName
			if !FileManager.default.fileExists(atPath: srcParentPath + name) {
				guard let alt = correctExt(name) else { return nil }
				name = alt
			}
			return try? Data(contentsOf: URL(fileURLWithPath: srcParentPath + name))
		}
		let archive = ArchiveReader(url: srcFile)
		if let d = try? archive.data(named: srcImageFileName) { return d }
		if let alt = correctExt(srcImageFileName) { return try? archive.data(named: alt) }
		return nil
	}

	public func image(_ idx: Int) -> CGImage? {
		guard idx >= 0 && idx < imageFileNames.count else { return nil }
		return image(imageFileNames[idx])
	}

	public func image(_ srcImageFileName: String) -> CGImage? {
		guard let data = imageData(srcImageFileName) else { return nil }
		return ImageUtils.decode(data)
	}
}

/// File-name ordering used for image-only archives (port of `FileNameComparator`).
enum FileNameOrder {
	static func less(_ a: String, _ b: String) -> Bool { compare(a, b) < 0 }

	static func compare(_ o1: String, _ o2: String) -> Int {
		let c1 = o1.lowercased().jchars, c2 = o2.lowercased().jchars
		for i in 0..<min(c1.count, c2.count) {
			let diff = Int(replace(c1[i])) - Int(replace(c2[i]))
			if diff != 0 { return diff }
		}
		return c1.count - c2.count
	}

	private static func replace(_ c: JChar) -> JChar {
		switch c {
		case "_": return "/"
		case "一": return "一"
		case "二": return "一" + 1
		case "三": return "一" + 2
		case "四": return "一" + 3
		case "五": return "一" + 4
		case "六": return "一" + 5
		case "七": return "一" + 6
		case "八": return "一" + 7
		case "九": return "一" + 8
		case "十": return "一" + 9
		case "上": return "上"
		case "前": return "上" + 1
		case "中": return "上" + 2
		case "下": return "上" + 3
		case "後": return "上" + 4
		default: return c
		}
	}
}
