import SwiftUI

/// Colors from the traditional Japanese palette, used for accents and generated covers.
enum Washi {
	static let paper = Color("Paper")
	static let ink = Color(red: 0.16, green: 0.15, blue: 0.14)
	static let vermilion = Color(red: 0.82, green: 0.26, blue: 0.18)   // 朱
	static let indigo = Color(red: 0.13, green: 0.23, blue: 0.37)      // 藍
	static let shelf = Color(red: 0.55, green: 0.39, blue: 0.25)

	/// Cover colors: 藍 朱 鶯 紫 茶 墨 群青 萌黄
	static let coverPalette: [(Color, Color)] = [
		(Color(red: 0.13, green: 0.23, blue: 0.37), Color(red: 0.92, green: 0.88, blue: 0.80)),
		(Color(red: 0.75, green: 0.24, blue: 0.17), Color(red: 0.98, green: 0.94, blue: 0.86)),
		(Color(red: 0.45, green: 0.44, blue: 0.20), Color(red: 0.96, green: 0.94, blue: 0.84)),
		(Color(red: 0.42, green: 0.30, blue: 0.53), Color(red: 0.95, green: 0.91, blue: 0.88)),
		(Color(red: 0.50, green: 0.30, blue: 0.22), Color(red: 0.97, green: 0.92, blue: 0.84)),
		(Color(red: 0.20, green: 0.20, blue: 0.21), Color(red: 0.90, green: 0.86, blue: 0.78)),
		(Color(red: 0.16, green: 0.32, blue: 0.56), Color(red: 0.94, green: 0.92, blue: 0.86)),
		(Color(red: 0.36, green: 0.48, blue: 0.24), Color(red: 0.96, green: 0.95, blue: 0.86)),
	]

	static func coverColors(for seed: String) -> (Color, Color) {
		var h: UInt64 = 5381
		for u in seed.unicodeScalars { h = (h &* 33) &+ UInt64(u.value) }
		return coverPalette[Int(h % UInt64(coverPalette.count))]
	}
}

/// Warm paper with a faint fiber texture.
struct PaperBackground: View {
	var body: some View {
		ZStack {
			Washi.paper
			Canvas { ctx, size in
				var rng = SplitMix(seed: 42)
				for _ in 0..<Int(size.width * size.height / 900) {
					let x = CGFloat(rng.next() % 10_000) / 10_000 * size.width
					let y = CGFloat(rng.next() % 10_000) / 10_000 * size.height
					let len = CGFloat(rng.next() % 14) + 3
					let angle = CGFloat(rng.next() % 628) / 100
					var p = Path()
					p.move(to: CGPoint(x: x, y: y))
					p.addLine(to: CGPoint(x: x + cos(angle) * len, y: y + sin(angle) * len))
					ctx.stroke(p, with: .color(.brown.opacity(0.05)), lineWidth: 0.6)
				}
			}
			.allowsHitTesting(false)
		}
		.ignoresSafeArea()
	}
}

struct SplitMix {
	var state: UInt64
	init(seed: UInt64) { state = seed }
	mutating func next() -> UInt64 {
		state &+= 0x9E37_79B9_7F4A_7C15
		var z = state
		z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
		z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
		return z ^ (z >> 31)
	}
}

/// A red seal stamped on finished books.
struct HankoStamp: View {
	var text = "完"
	@State private var stamped = false

	var body: some View {
		Text(text)
			.font(.custom("Hiragino Mincho ProN", size: 22).weight(.heavy))
			.foregroundStyle(Washi.vermilion)
			.frame(width: 40, height: 40)
			.overlay(RoundedRectangle(cornerRadius: 7).stroke(Washi.vermilion, lineWidth: 3))
			.rotationEffect(.degrees(-12))
			.scaleEffect(stamped ? 1 : 2.2)
			.opacity(stamped ? 0.92 : 0)
			.onAppear {
				withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) { stamped = true }
			}
			.accessibilityLabel("Done")
	}
}

/// Vertical Japanese type: columns of up to `perColumn` characters, laid out right to left.
struct VerticalText: View {
	let text: String
	var size: CGFloat
	var weight: Font.Weight = .semibold
	var perColumn = 9
	var maxColumns = 3

	var body: some View {
		let chars = Array(text)
		let columns = stride(from: 0, to: min(chars.count, perColumn * maxColumns), by: perColumn).map { Array(chars[$0..<min($0 + perColumn, chars.count)]) }
		HStack(alignment: .top, spacing: size * 0.25) {
			// right-to-left: first column on the right
			ForEach(Array(columns.enumerated().reversed()), id: \.offset) { _, column in
				VStack(spacing: -size * 0.08) {
					ForEach(Array(column.enumerated()), id: \.offset) { _, ch in
						Text(String(Self.vertical(ch)))
							.font(.custom("Hiragino Mincho ProN", size: size).weight(weight))
							.rotationEffect(Self.rotates(ch) ? .degrees(90) : .zero)
					}
				}
			}
		}
	}

	/// Vertical presentation forms for punctuation.
	static func vertical(_ c: Character) -> Character {
		switch c {
		case "ー", "―", "─": return "｜"
		case "、": return "︑"
		case "。": return "︒"
		case "「": return "﹁"
		case "」": return "﹂"
		case "『": return "﹃"
		case "』": return "﹄"
		case "（", "(": return "︵"
		case "）", ")": return "︶"
		case "…": return "︙"
		default: return c
		}
	}

	static func rotates(_ c: Character) -> Bool { c.isASCII && c.isLetter }
}

/// A cover drawn from the title, for books without an illustration.
struct GeneratedCover: View {
	let title: String
	let author: String
	/// width / height
	var aspect: CGFloat = 3 / 4

	var body: some View {
		let (bg, fg) = Washi.coverColors(for: title + author)
		GeometryReader { geo in
			let w = geo.size.width
			ZStack {
				bg
				// border frame like old bunko covers
				Rectangle()
					.stroke(fg.opacity(0.55), lineWidth: max(1, w * 0.012))
					.padding(w * 0.07)
				let titleText = title.isEmpty ? "無題" : title
				let long = titleText.count > 7
				HStack(alignment: .top, spacing: w * 0.06) {
					VerticalText(text: author, size: w * 0.075, weight: .regular, perColumn: 10, maxColumns: 1)
						.foregroundStyle(fg.opacity(0.85))
						.padding(.top, w * (long ? 0.62 : 0.55))
					VerticalText(text: titleText, size: w * (long ? 0.105 : 0.15), perColumn: long ? 8 : 7, maxColumns: 3)
						.foregroundStyle(fg)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
				.padding(.top, w * 0.16)
				.padding(.trailing, w * 0.16)
			}
		}
		.aspectRatio(aspect, contentMode: .fit)
	}
}

extension View {
	/// The soft lift used for book covers.
	func bookShadow() -> some View {
		shadow(color: .black.opacity(0.18), radius: 1, x: 0, y: 1)
			.shadow(color: .black.opacity(0.22), radius: 8, x: 2, y: 6)
	}
}
