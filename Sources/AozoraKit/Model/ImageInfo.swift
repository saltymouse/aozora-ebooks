import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Size and format of an image referenced by the book (port of `ImageInfo`).
public final class ImageInfo: VelocityObject {
	/// "0001"
	var id: String?
	/// "0001.png"
	var outFileName: String?
	/// png, jpeg, gif …
	var ext: String
	public var width: Int
	public var height: Int
	var outWidth = -1
	var outHeight = -1
	var zipIndex: Int
	var isCover = false
	/// 90 = right, -90 = left
	var rotateAngle = 0

	init(_ ext: String, _ width: Int, _ height: Int, _ zipIndex: Int = -1) {
		self.ext = ext.lowercased()
		self.width = width
		self.height = height
		self.zipIndex = zipIndex
	}

	/// Reads only the header: format and pixel size, like Java's ImageReader.
	static func read(_ data: Data, zipIndex: Int = -1) -> ImageInfo? {
		guard let src = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
		      let type = CGImageSourceGetType(src) as String?,
		      let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
		      let w = props[kCGImagePropertyPixelWidth] as? Int,
		      let h = props[kCGImagePropertyPixelHeight] as? Int else { return nil }
		return ImageInfo(formatName(type), w, h, zipIndex)
	}

	static func read(_ url: URL) -> ImageInfo? {
		guard let data = try? Data(contentsOf: url) else { return nil }
		return read(data)
	}

	/// ImageIO format names as Java reports them.
	static func formatName(_ uti: String) -> String {
		switch uti {
		case UTType.png.identifier: return "png"
		case UTType.jpeg.identifier: return "jpeg"
		case UTType.gif.identifier: return "gif"
		case UTType.bmp.identifier: return "bmp"
		default: return UTType(uti)?.preferredFilenameExtension ?? "unknown"
		}
	}

	/// MIME type for package.opf.
	var format: String { "image/" + (ext == "jpg" ? "jpeg" : ext) }

	public func vproperty(_ name: String) -> VValue {
		switch name {
		case "id": return .from(id)
		case "outfilename": return .from(outFileName)
		case "ext": return .string(ext)
		case "format": return .string(format)
		case "iscover": return .bool(isCover)
		case "width": return .int(width)
		case "height": return .int(height)
		case "outwidth": return .int(outWidth)
		case "outheight": return .int(outHeight)
		default: return .undefined
		}
	}
}
