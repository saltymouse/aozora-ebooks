import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Image resizing, margin trimming and encoding (port of `ImageUtils`).
enum ImageUtils {
	static let nombreTop = 1
	static let nombreBottom = 2
	static let nombreTopBottom = 3

	/// Parameters shared by every image written to one book.
	struct WriteParams {
		var jpegQuality: Float = 0.8
		/// Lookup table for gamma correction, or nil.
		var gamma: [UInt8]?
		var maxImagePixels = 0
		var maxImageW = 0
		var maxImageH = 0
		var dispW = 600
		var dispH = 800
		var autoMarginLimitH = 0
		var autoMarginLimitV = 0
		var autoMarginWhiteLevel = 100
		var autoMarginPadding: Float = 0
		var autoMarginNombre = 0
		var nombreSize: Float = 0.03

		static func gammaTable(_ gamma: Float) -> [UInt8]? {
			guard gamma != 1 else { return nil }
			return (0..<256).map { i in UInt8(min(255, (255 * pow(Double(i) / 255.0, 1 / Double(gamma))).rounded())) }
		}
	}

	static func decode(_ data: Data) -> CGImage? {
		guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
		return CGImageSourceCreateImageAtIndex(src, 0, nil)
	}

	static func load(_ path: String) -> CGImage? {
		let data: Data?
		if path.hasPrefix("http"), let url = URL(string: path) {
			data = try? Data(contentsOf: url)
		} else {
			data = FileManager.default.contents(atPath: path)
		}
		return data.flatMap(decode)
	}

	/// Resizes/trims/rotates as configured and encodes in the image's own format.
	/// Returns the original bytes untouched when nothing needs to change.
	/// Updates `info.outWidth/outHeight`.
	static func writeImage(_ srcData: Data?, _ srcImageIn: CGImage?, _ info: ImageInfo, _ p: WriteParams, log: Log) -> Data? {
		let ext = info.ext
		let imgW = info.width, imgH = info.height
		var w = imgW, h = imgH
		info.outWidth = imgW
		info.outHeight = imgH
		var srcImage = srcImageIn

		if srcImage == nil && (info.rotateAngle != 0 || p.gamma != nil) { srcImage = srcData.flatMap(decode) }

		var margin: [Int]? = nil
		if p.autoMarginLimitH > 0 || p.autoMarginLimitV > 0 {
			let startPixel = Int(Double(w) * 0.01)
			let ignoreEdge = Int(Double(w) * 0.03)
			let dustSize = Int(Double(w) * 0.01)
			if srcImage == nil { srcImage = srcData.flatMap(decode) }
			if let srcImage, let pixels = Pixels(srcImage) {
				var mg = getPlainMargin(pixels, Float(p.autoMarginLimitH) / 100, Float(p.autoMarginLimitV) / 100, Float(p.autoMarginWhiteLevel) / 100, p.autoMarginPadding / 100, startPixel, ignoreEdge, dustSize, p.autoMarginNombre, p.nombreSize)
				if mg != [0, 0, 0, 0] {
					var mw = w - mg[0] - mg[2]
					var mh = h - mg[1] - mg[3]
					let dWH = Double(p.dispW) / Double(p.dispH)
					let mWH = Double(mw) / Double(mh)
					// Keep the fit direction (width vs height) the same after trimming.
					if Double(w) / Double(h) < dWH {
						if mWH > dWH && mw > p.dispW {
							mh = Int(Double(mw) / dWH)
							mg[3] = h - mg[1] - mh
							if mg[3] < 0 { mg[3] = 0; mg[1] = h - mh }
						}
					} else if mWH < dWH && mh > p.dispH {
						mw = Int(Double(mh) * dWH)
						let mLR = Double(mg[0] + mg[2])
						mg[0] = Int(Double(w - mw) * Double(mg[0]) / mLR)
						mg[2] = Int(Double(w - mw) * Double(mg[2]) / mLR)
					}
					w = mw
					h = mh
					margin = mg
				}
			}
		}

		var scale = 1.0
		if p.maxImagePixels >= 10000 { scale = sqrt(Double(p.maxImagePixels) / Double(w * h)) }
		if p.maxImageW > 0 { scale = min(scale, Double(p.maxImageW) / Double(w)) }
		if p.maxImageH > 0 { scale = min(scale, Double(p.maxImageH) / Double(h)) }

		if scale >= 1 {
			guard var image = srcImage else { return srcData } // unchanged: copy as-is
			if margin == nil && info.rotateAngle == 0 && p.gamma == nil, let srcData { return srcData }
			if info.rotateAngle != 0 {
				guard let rotated = render(image, outW: h, outH: w, rotate: info.rotateAngle, margin: margin) else { return srcData }
				image = rotated
				log.println("画像回転: \(info.outFileName ?? "") (\(h),\(w))")
			} else if let m = margin {
				image = image.cropping(to: CGRect(x: m[0], y: m[1], width: image.width - m[2] - m[0], height: image.height - m[3] - m[1])) ?? image
			}
			if let g = p.gamma { image = applyGamma(image, g) ?? image }
			info.outWidth = image.width
			info.outHeight = image.height
			return encode(image, ext, p.jpegQuality) ?? srcData
		}

		var scaledW = Int(Double(w) * scale + 0.5)
		var scaledH = Int(Double(h) * scale + 0.5)
		if info.rotateAngle != 0 {
			scaledW = Int(Double(h) * scale + 0.5)
			scaledH = Int(Double(w) * scale + 0.5)
		}
		if srcImage == nil { srcImage = srcData.flatMap(decode) }
		guard let src = srcImage,
		      var out = render(src, outW: scaledW, outH: scaledH, rotate: info.rotateAngle, margin: margin) else {
			log.println("画像読み込みエラー: \(info.outFileName ?? "")")
			return nil
		}
		if let g = p.gamma { out = applyGamma(out, g) ?? out }
		info.outWidth = out.width
		info.outHeight = out.height
		log.println("画像縮小\(info.rotateAngle != 0 ? "回転" : ""): \(info.outFileName ?? "") (\(w),\(h))→(\(scaledW),\(scaledH))")
		return encode(out, ext, p.jpegQuality)
	}

	/// Crops `margin` (left, top, right, bottom) off `src`, then draws it scaled into
	/// outW x outH on white, rotated 90° clockwise ("right") or counter-clockwise ("left").
	private static func render(_ src: CGImage, outW: Int, outH: Int, rotate: Int, margin: [Int]?) -> CGImage? {
		var image = src
		if let m = margin {
			image = src.cropping(to: CGRect(x: m[0], y: m[1], width: src.width - m[0] - m[2], height: src.height - m[1] - m[3])) ?? src
		}
		let gray = src.colorSpace?.model == .monochrome
		let cs = gray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB()
		let info = gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
		guard outW > 0, outH > 0,
		      let ctx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0, space: cs, bitmapInfo: info) else { return nil }
		ctx.interpolationQuality = .high
		ctx.setFillColor(gray ? CGColor(gray: 1, alpha: 1) : CGColor(red: 1, green: 1, blue: 1, alpha: 1))
		ctx.fill(CGRect(x: 0, y: 0, width: outW, height: outH))
		switch rotate {
		case 90:
			ctx.translateBy(x: 0, y: CGFloat(outH))
			ctx.rotate(by: -.pi / 2)
			ctx.draw(image, in: CGRect(x: 0, y: 0, width: outH, height: outW))
		case -90, 270:
			ctx.translateBy(x: CGFloat(outW), y: 0)
			ctx.rotate(by: .pi / 2)
			ctx.draw(image, in: CGRect(x: 0, y: 0, width: outH, height: outW))
		default:
			ctx.draw(image, in: CGRect(x: 0, y: 0, width: outW, height: outH))
		}
		return ctx.makeImage()
	}

	private static func applyGamma(_ src: CGImage, _ table: [UInt8]) -> CGImage? {
		guard let px = Pixels(src) else { return nil }
		var data = px.data
		for i in stride(from: 0, to: data.count, by: 4) {
			data[i] = table[Int(data[i])]
			data[i + 1] = table[Int(data[i + 1])]
			data[i + 2] = table[Int(data[i + 2])]
		}
		guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
		return CGImage(width: px.width, height: px.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: px.width * 4,
		               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
		               provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
	}

	/// Encodes as png, jpeg or gif (matching the source extension).
	static func encode(_ image: CGImage, _ ext: String, _ jpegQuality: Float) -> Data? {
		let type: UTType
		var props: [CFString: Any] = [:]
		switch ext {
		case "png": type = .png
		case "gif": type = .gif
		case "bmp": type = .bmp
		default:
			type = .jpeg
			props[kCGImageDestinationLossyCompressionQuality] = jpegQuality
		}
		let out = NSMutableData()
		guard let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
		CGImageDestinationAddImage(dest, image, props as CFDictionary)
		guard CGImageDestinationFinalize(dest) else { return nil }
		return out as Data
	}

	// MARK: Margin detection

	/// RGBA8 pixel buffer for margin scanning.
	struct Pixels {
		let width: Int
		let height: Int
		let data: [UInt8]

		init?(_ image: CGImage) {
			let width = image.width, height = image.height
			self.width = width
			self.height = height
			if image.colorSpace?.model == .monochrome && image.bitsPerComponent <= 8 {
				// Java reads gray images as TYPE_BYTE_GRAY, whose getRGB() maps linear gray to sRGB.
				var gray = [UInt8](repeating: 255, count: width * height)
				let ok = gray.withUnsafeMutableBytes { raw -> Bool in
					guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
					                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
					ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
					return true
				}
				guard ok else { return nil }
				var buf = [UInt8](repeating: 255, count: width * height * 4)
				for i in 0..<gray.count {
					let v = Pixels.javaGrayToRGB[Int(gray[i])]
					buf[i * 4] = v; buf[i * 4 + 1] = v; buf[i * 4 + 2] = v
				}
				data = buf
				return
			}
			var buf = [UInt8](repeating: 255, count: width * height * 4)
			let ok = buf.withUnsafeMutableBytes { raw -> Bool in
				guard let ctx = CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
				                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
				ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
				ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
				ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
				return true
			}
			guard ok else { return nil }
			data = buf
		}

		/// `BufferedImage.TYPE_BYTE_GRAY.getRGB()` channel value for each gray level (dumped from Java).
		static let javaGrayToRGB: [UInt8] = [
			0, 13, 22, 28, 34, 38, 42, 46, 50, 53, 56, 59, 61, 64, 66, 69,
			71, 73, 75, 77, 79, 81, 83, 85, 86, 88, 90, 92, 93, 95, 96, 98,
			99, 101, 102, 104, 105, 106, 108, 109, 110, 112, 113, 114, 115, 117, 118, 119,
			120, 121, 122, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136,
			137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 148, 149, 150, 151,
			152, 153, 154, 155, 155, 156, 157, 158, 159, 159, 160, 161, 162, 163, 163, 164,
			165, 166, 167, 167, 168, 169, 170, 170, 171, 172, 173, 173, 174, 175, 175, 176,
			177, 178, 178, 179, 180, 180, 181, 182, 182, 183, 184, 185, 185, 186, 187, 187,
			188, 189, 189, 190, 190, 191, 192, 192, 193, 194, 194, 195, 196, 196, 197, 197,
			198, 199, 199, 200, 200, 201, 202, 202, 203, 203, 204, 205, 205, 206, 206, 207,
			208, 208, 209, 209, 210, 210, 211, 212, 212, 213, 213, 214, 214, 215, 215, 216,
			216, 217, 218, 218, 219, 219, 220, 220, 221, 221, 222, 222, 223, 223, 224, 224,
			225, 226, 226, 227, 227, 228, 228, 229, 229, 230, 230, 231, 231, 232, 232, 233,
			233, 234, 234, 235, 235, 236, 236, 237, 237, 238, 238, 238, 239, 239, 240, 240,
			241, 241, 242, 242, 243, 243, 244, 244, 245, 245, 246, 246, 246, 247, 247, 248,
			248, 249, 249, 250, 250, 251, 251, 251, 252, 252, 253, 253, 254, 254, 255, 255,
		]

		/// True if any channel is darker than the limit (y from the top).
		@inline(__always) func isColored(_ x: Int, _ y: Int, _ rgbLimit: Int) -> Bool {
			let i = (y * width + x) * 4
			return rgbLimit > Int(data[i]) || rgbLimit > Int(data[i + 1]) || rgbLimit > Int(data[i + 2])
		}
	}

	/// Margins to remove, as pixels (left, top, right, bottom).
	static func getPlainMargin(_ image: Pixels, _ limitH: Float, _ limitV: Float, _ whiteLevel: Float, _ padding: Float, _ startPixel: Int, _ ignoreEdge: Int, _ dustSize: Int, _ nombreType: Int, _ nombreSize: Float) -> [Int] {
		var margin = [0, 0, 0, 0]
		let width = image.width, height = image.height
		let rgbLimit = Int(256 * whiteLevel)
		let paddingH = max(1, Int(Float(width) * padding))
		let paddingV = max(1, Int(Float(height) * padding))
		let limitPxH = Int(Float(width) * limitH)
		let limitPxV = Int(Float(height) * limitV) / 2
		var limitPxT = Int(Float(height) * limitV) / 2
		var limitPxB = Int(Float(height) * limitV) / 2
		if nombreType == nombreTop || nombreType == nombreTopBottom { limitPxT += Int(Double(height) * 0.05) }
		if nombreType == nombreBottom || nombreType == nombreTopBottom { limitPxB += Int(Double(height) * 0.05) }
		let ignoreEdgeR = ignoreEdge

		func rowColored(_ y: Int, _ dust: Int) -> Int { coloredPixelsH(image, width, y, rgbLimit, 0, ignoreEdge, ignoreEdgeR, dust) }

		// top
		var colored = rowColored(startPixel, dustSize)
		if colored > 0 {
			var i = startPixel - 1
			while i >= 0 { colored = rowColored(i, 0); margin[1] = i; if colored == 0 { break }; i -= 1 }
		} else {
			margin[1] = startPixel
			var i = startPixel + 1
			while i <= limitPxT { if rowColored(i, dustSize) == 0 { margin[1] = i } else { break }; i += 1 }
		}
		// bottom
		colored = rowColored(height - 1 - startPixel, dustSize)
		if colored > 0 {
			var i = startPixel - 1
			while i >= 0 { colored = rowColored(height - 1 - i, 0); margin[3] = i; if colored == 0 { break }; i -= 1 }
		} else {
			margin[3] = startPixel
			var i = startPixel + 1
			while i <= limitPxB { if rowColored(height - 1 - i, dustSize) == 0 { margin[3] = i } else { break }; i += 1 }
		}

		var hasNombreT = false, hasNombreB = false
		if nombreType == nombreTop || nombreType == nombreTopBottom {
			let nombreLimit = Int(Float(height) * nombreSize) + margin[1]
			let nombreDust = Int(Double(height) * 0.005)
			var nombreEnd = 0
			var i = margin[1] + 1
			while i <= nombreLimit {
				if rowColored(i, 0) == 0 { nombreEnd = i; if nombreEnd - margin[1] > nombreDust { break } }
				i += 1
			}
			if Double(nombreEnd) > Double(margin[1]) + Double(height) * 0.005 && nombreEnd <= nombreLimit {
				var whiteEnd = nombreEnd
				var j = nombreEnd + 1
				while j <= limitPxT {
					if rowColored(j, dustSize) == 0 { whiteEnd = j } else if j - nombreEnd > nombreDust { break }
					j += 1
				}
				if Double(whiteEnd) > Double(nombreEnd) + Double(height) * 0.01 { margin[1] = whiteEnd; hasNombreT = true }
			}
		}
		if nombreType == nombreBottom || nombreType == nombreTopBottom {
			let nombreLimit = Int(Float(height) * nombreSize) + margin[3]
			let nombreDust = Int(Double(height) * 0.005)
			var nombreEnd = 0
			var i = margin[3] + 1
			while i <= nombreLimit {
				if rowColored(height - 1 - i, 0) == 0 { nombreEnd = i; if nombreEnd - margin[3] > nombreDust { break } }
				i += 1
			}
			if Double(nombreEnd) > Double(margin[3]) + Double(height) * 0.005 && nombreEnd <= nombreLimit {
				var whiteEnd = nombreEnd
				var j = nombreEnd + 1
				while j <= limitPxB {
					if rowColored(height - 1 - j, dustSize) == 0 { whiteEnd = j } else if j - nombreEnd > nombreDust { break }
					j += 1
				}
				if Double(whiteEnd) > Double(nombreEnd) + Double(height) * 0.01 { margin[3] = whiteEnd; hasNombreB = true }
			}
		}

		let ignoreTop = max(ignoreEdge, margin[1])
		let ignoreBottom = max(ignoreEdge, margin[3])
		func colColored(_ x: Int, _ dust: Int) -> Int { coloredPixelsV(image, height, x, rgbLimit, 0, ignoreTop, ignoreBottom, dust) }
		// left
		colored = colColored(startPixel, dustSize)
		if colored > 0 {
			var i = startPixel - 1
			while i >= 0 { colored = colColored(i, 0); margin[0] = i; if colored == 0 { break }; i -= 1 }
		} else {
			margin[0] = startPixel
			var i = startPixel + 1
			while i <= limitPxH { if colColored(i, dustSize) == 0 { margin[0] = i } else { break }; i += 1 }
		}
		// right
		colored = colColored(width - 1 - startPixel, dustSize)
		if colored > 0 {
			var i = startPixel - 1
			while i >= 0 { colored = colColored(width - 1 - i, 0); margin[2] = i; if colored == 0 { break }; i -= 1 }
		} else {
			margin[2] = startPixel
			var i = startPixel + 1
			while i <= limitPxH { if colColored(width - 1 - i, dustSize) == 0 { margin[2] = i } else { break }; i += 1 }
		}

		if margin[0] + margin[2] > limitPxH {
			let rate = Double(limitPxH) / Double(margin[0] + margin[2])
			margin[0] = Int(Double(margin[0]) * rate)
			margin[2] = Int(Double(margin[2]) * rate)
		}
		if !hasNombreT { margin[1] = min(margin[1], limitPxV) }
		if !hasNombreB { margin[3] = min(margin[3], limitPxV) }
		margin[0] = max(0, margin[0] - paddingH)
		margin[1] = max(0, margin[1] - paddingV)
		margin[2] = max(0, margin[2] - paddingH)
		margin[3] = max(0, margin[3] - paddingV)
		return margin
	}

	private static func coloredPixelsH(_ img: Pixels, _ w: Int, _ offsetY: Int, _ rgbLimit: Int, _ limitPixel: Int, _ ignoreEdgeL: Int, _ ignoreEdgeR: Int, _ dustSize: Int) -> Int {
		guard offsetY >= 0 && offsetY < img.height else { return 0 }
		var colored = 0
		var x = w - 1 - ignoreEdgeR
		while x >= ignoreEdgeL {
			if img.isColored(x, offsetY, rgbLimit) && (dustSize < 4 || !isDust(img, x, img.width, offsetY, img.height, dustSize, rgbLimit)) {
				colored += 1
				if limitPixel < colored { return colored }
			}
			x -= 1
		}
		return colored
	}

	private static func coloredPixelsV(_ img: Pixels, _ h: Int, _ offsetX: Int, _ rgbLimit: Int, _ limitPixel: Int, _ ignoreTop: Int, _ ignoreBottom: Int, _ dustSize: Int) -> Int {
		guard offsetX >= 0 && offsetX < img.width else { return 0 }
		var colored = 0
		var y = h - 1 - ignoreBottom
		while y >= ignoreTop {
			if img.isColored(offsetX, y, rgbLimit) && (dustSize < 4 || !isDust(img, offsetX, img.width, y, img.height, dustSize, rgbLimit)) {
				colored += 1
				if limitPixel < colored { return colored }
			}
			y -= 1
		}
		return colored
	}

	private static func isDust(_ img: Pixels, _ curX: Int, _ maxXIn: Int, _ curY: Int, _ maxYIn: Int, _ dustSize: Int, _ rgbLimit: Int) -> Bool {
		if dustSize == 0 { return false }
		let minX = max(0, curX - dustSize - 1)
		let maxX = min(maxXIn, curX + dustSize + 1)
		let minY = max(0, curY - dustSize - 1)
		let maxY = min(maxYIn, curY + dustSize + 1)

		var h = 1
		var y = curY - 1
		while y >= minY { if img.isColored(curX, y, rgbLimit) { h += 1 } else { break }; y -= 1 }
		y = curY + 1
		while y < maxY { if img.isColored(curX, y, rgbLimit) { h += 1 } else { break }; y += 1 }
		if h > dustSize { return false }

		var w = 1
		var x = curX - 1
		while x >= minX { if img.isColored(x, curY, rgbLimit) { w += 1 } else { break }; x -= 1 }
		x = curX + 1
		while x < maxX { if img.isColored(x, curY, rgbLimit) { w += 1 } else { break }; x += 1 }
		if w > dustSize { return false }

		func columnCount(_ x: Int) -> Int { (minY..<maxY).reduce(0) { $0 + (img.isColored(x, $1, rgbLimit) ? 1 : 0) } }
		func rowCount(_ y: Int) -> Int { (minX..<maxX).reduce(0) { $0 + (img.isColored($1, y, rgbLimit) ? 1 : 0) } }

		w = 1
		x = curX - 1
		while x >= minX { let c = columnCount(x); if c > dustSize { return false }; if c == 0 { break }; w += 1; x -= 1 }
		x = curX + 1
		while x < maxX { let c = columnCount(x); if c > dustSize { return false }; if c == 0 { break }; w += 1; x += 1 }
		if w > dustSize { return false }

		h = 1
		y = curY - 1
		while y >= minY { let c = rowCount(y); if c > dustSize { return false }; if c == 0 { break }; h += 1; y -= 1 }
		y = curY + 1
		while y < maxY { let c = rowCount(y); if c > dustSize { return false }; if c == 0 { break }; h += 1; y += 1 }
		return h <= dustSize
	}
}
