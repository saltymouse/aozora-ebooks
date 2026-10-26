// Draws the app icon: an indigo bunko book with 青 and a vermilion seal on washi.
// usage: swift scripts/make_icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset
import AppKit

let out = CommandLine.arguments[1]
func render(_ px: Int) -> Data {
	let s = CGFloat(px)
	let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
		let ctx = NSGraphicsContext.current!.cgContext
		// macOS icon grid: 824/1024 content square
		let inset = s * 100 / 1024
		let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
		let radius = rect.width * 0.225
		ctx.saveGState()
		ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.35).cgColor)
		let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
		NSColor(srgbRed: 0.965, green: 0.937, blue: 0.89, alpha: 1).setFill()
		bg.fill()
		ctx.restoreGState()
		NSGraphicsContext.current!.saveGraphicsState()
		bg.addClip()
		// paper fibers
		var seed: UInt64 = 7
		func rnd() -> CGFloat { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(seed >> 33) / CGFloat(1 << 31) }
		NSColor.brown.withAlphaComponent(0.07).setStroke()
		for _ in 0..<Int(s * 0.6) {
			let p = NSBezierPath()
			let x = rect.minX + rnd() * rect.width, y = rect.minY + rnd() * rect.height, a = rnd() * 6.28, l = s * (0.01 + rnd() * 0.02)
			p.move(to: CGPoint(x: x, y: y)); p.line(to: CGPoint(x: x + cos(a) * l, y: y + sin(a) * l))
			p.lineWidth = max(0.5, s / 900); p.stroke()
		}
		// book
		let bw = rect.width * 0.52, bh = bw * 1.38
		let book = CGRect(x: rect.midX - bw / 2 - rect.width * 0.03, y: rect.midY - bh / 2, width: bw, height: bh)
		ctx.saveGState()
		ctx.setShadow(offset: CGSize(width: s * 0.012, height: -s * 0.02), blur: s * 0.035, color: NSColor.black.withAlphaComponent(0.4).cgColor)
		NSColor(srgbRed: 0.13, green: 0.23, blue: 0.37, alpha: 1).setFill()
		NSBezierPath(roundedRect: book, xRadius: s * 0.012, yRadius: s * 0.012).fill()
		ctx.restoreGState()
		// spine shading
		let spine = CGRect(x: book.minX, y: book.minY, width: bw * 0.07, height: bh)
		NSGradient(starting: NSColor.black.withAlphaComponent(0.35), ending: .clear)!.draw(in: spine, angle: 0)
		// frame line
		NSColor(srgbRed: 0.92, green: 0.88, blue: 0.80, alpha: 0.55).setStroke()
		let frame = NSBezierPath(rect: book.insetBy(dx: bw * 0.08, dy: bw * 0.08)); frame.lineWidth = s * 0.006; frame.stroke()
		// 青
		let font = NSFont(name: "Hiragino Mincho ProN W6", size: bw * 0.56) ?? NSFont.systemFont(ofSize: bw * 0.56, weight: .bold)
		let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(srgbRed: 0.96, green: 0.94, blue: 0.88, alpha: 1)]
		let glyph = NSAttributedString(string: "青", attributes: attrs)
		let gs = glyph.size()
		glyph.draw(at: CGPoint(x: book.midX - gs.width / 2 + bw * 0.02, y: book.midY - gs.height / 2 + bh * 0.08))
		// seal
		let sealSize = rect.width * 0.2
		let seal = CGRect(x: book.maxX - sealSize * 0.45, y: book.minY + bh * 0.06, width: sealSize, height: sealSize)
		ctx.saveGState()
		ctx.translateBy(x: seal.midX, y: seal.midY)
		ctx.rotate(by: -0.2)
		let sr = CGRect(x: -sealSize / 2, y: -sealSize / 2, width: sealSize, height: sealSize)
		let vermilion = NSColor(srgbRed: 0.82, green: 0.26, blue: 0.18, alpha: 0.95)
		vermilion.setFill()
		NSBezierPath(roundedRect: sr, xRadius: sealSize * 0.16, yRadius: sealSize * 0.16).fill()
		let sfont = NSFont(name: "Hiragino Mincho ProN W6", size: sealSize * 0.62) ?? NSFont.systemFont(ofSize: sealSize * 0.62, weight: .heavy)
		let st = NSAttributedString(string: "完", attributes: [.font: sfont, .foregroundColor: NSColor(srgbRed: 0.98, green: 0.95, blue: 0.9, alpha: 1)])
		let ss = st.size()
		st.draw(at: CGPoint(x: -ss.width / 2, y: -ss.height / 2))
		ctx.restoreGState()
		NSGraphicsContext.current!.restoreGraphicsState()
		return true
	}
	let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
	NSGraphicsContext.saveGraphicsState()
	NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
	img.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
	NSGraphicsContext.restoreGraphicsState()
	return rep.representation(using: .png, properties: [:])!
}

var images: [String] = []
for (size, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
	for scale in scales {
		let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
		try! render(size * scale).write(to: URL(fileURLWithPath: out + "/" + name))
		images.append(#"{ "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(size)x\#(size)", "filename" : "\#(name)" }"#)
	}
}
try! ("{ \"images\" : [\n" + images.joined(separator: ",\n") + "\n], \"info\" : { \"author\" : \"xcode\", \"version\" : 1 } }\n").write(toFile: out + "/Contents.json", atomically: true, encoding: .utf8)
