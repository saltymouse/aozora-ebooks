import SwiftUI
import AozoraKit
import UniformTypeIdentifiers

/// What the cover will be, and how it's framed.
struct CoverState {
	enum Source: Equatable {
		case none
		case illustration(Int)
		case file(String)
		case generated
	}

	var source: Source = .none
	var image: CGImage?
	/// 1 = whole image fits in the frame.
	var zoom: CGFloat = 1
	/// Pan in frame points.
	var offset: CGSize = .zero
	/// Frame size the offset refers to.
	var frame: CGSize = CGSize(width: 300, height: 400)

	init() {}

	init(book: PreparedBook, image: CGImage?) {
		self.image = image
		let info = book.bookInfo
		if info.coverImageIndex >= 0 { source = .illustration(info.coverImageIndex) }
		else if let f = info.coverFileName, !f.isEmpty { source = .file(f) }
		else { source = .none }
	}

	var isAdjusted: Bool { zoom != 1 || offset != .zero }

	/// The choice handed to the engine.
	@MainActor func resolve(coverW: Int, coverH: Int, keepOriginal: Bool, title: String, author: String) -> PreparedBook.Cover {
		switch source {
		case .none:
			return .none
		case .generated:
			if let rendered = renderGenerated(title: title, author: author, width: coverW, height: coverH) { return .edited(rendered, keepOriginal: true) }
			return .none
		case .illustration(let i):
			if isAdjusted, let r = renderCrop(coverW: coverW, coverH: coverH) { return .edited(r, keepOriginal: keepOriginal) }
			return .illustration(i)
		case .file(let f):
			if isAdjusted, let r = renderCrop(coverW: coverW, coverH: coverH) { return .edited(r, keepOriginal: true) }
			return .file(f)
		}
	}

	/// Renders exactly what the frame shows, at cover size.
	func renderCrop(coverW: Int, coverH: Int) -> CGImage? {
		guard let image else { return nil }
		let W = CGFloat(image.width), H = CGFloat(image.height)
		let k = min(frame.width / W, frame.height / H) * zoom
		// don't upscale beyond the source resolution
		let r = min(CGFloat(coverW) / frame.width, 1 / k)
		let ow = Int(frame.width * r), oh = Int(frame.height * r)
		guard ow > 0, oh > 0,
		      let ctx = CGContext(data: nil, width: ow, height: oh, bitsPerComponent: 8, bytesPerRow: 0,
		                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
		ctx.interpolationQuality = .high
		ctx.setFillColor(CGColor(gray: 1, alpha: 1))
		ctx.fill(CGRect(x: 0, y: 0, width: ow, height: oh))
		let x = ((frame.width - W * k) / 2 + offset.width) * r
		let yTop = ((frame.height - H * k) / 2 + offset.height) * r
		let h = H * k * r
		ctx.draw(image, in: CGRect(x: x, y: CGFloat(oh) - yTop - h, width: W * k * r, height: h))
		return ctx.makeImage()
	}

	@MainActor func renderGenerated(title: String, author: String, width: Int, height: Int) -> CGImage? {
		let aspect = CGFloat(width) / CGFloat(max(1, height))
		let renderer = ImageRenderer(content: GeneratedCover(title: title, author: author, aspect: aspect).frame(width: CGFloat(width) / 2, height: CGFloat(height) / 2))
		renderer.scale = 2
		return renderer.cgImage
	}
}

/// Pick, crop and zoom the cover.
struct CoverEditor: View {
	@Environment(AppModel.self) private var model
	let job: BookJob
	@Binding var state: CoverState
	var title: String
	var author: String

	@State private var thumbs: [Int: CGImage] = [:]
	/// Illustrations referenced by the text but missing or unreadable.
	@State private var missing = Set<Int>()
	@State private var dragStart: CGSize?
	@State private var zoomStart: CGFloat?
	@State private var dropTargeted = false

	private var aspect: CGFloat { CGFloat(model.settings.coverW) / CGFloat(max(1, model.settings.coverH)) }

	var body: some View {
		VStack(spacing: 12) {
			frameView
			zoomControls
			sourcePicker
		}
		.task { await loadThumbs() }
	}

	private var frameView: some View {
		GeometryReader { geo in
			ZStack {
				Color.white
				switch state.source {
				case .none:
					// preview what "Make One" would give
					GeneratedCover(title: title, author: author, aspect: aspect)
						.opacity(0.35)
						.saturation(0.3)
					VStack(spacing: 10) {
						Text("No cover").font(.headline)
						Button("Make One") {
							state.source = .generated
							resetFrame()
						}
						.buttonStyle(.borderedProminent)
						.tint(Washi.vermilion)
					}
				case .generated:
					GeneratedCover(title: title, author: author, aspect: aspect)
				default:
					if let image = state.image {
						Image(decorative: image, scale: 1)
							.resizable()
							.aspectRatio(contentMode: .fit)
							.scaleEffect(state.zoom)
							.offset(state.offset)
					} else {
						ProgressView()
					}
				}
			}
			.clipped()
			.contentShape(Rectangle())
			.gesture(panGesture)
			.gesture(magnifyGesture)
			.onAppear { state.frame = geo.size }
			.onChange(of: geo.size) { _, s in state.frame = s }
		}
		.aspectRatio(aspect, contentMode: .fit)
		.bookShadow()
		.overlay {
			if dropTargeted { RoundedRectangle(cornerRadius: 2).stroke(Washi.vermilion, lineWidth: 3) }
		}
		.dropDestination(for: URL.self) { urls, _ in
			guard let url = urls.first, let image = Self.load(url) else { return false }
			state.source = .file(url.path)
			state.image = image
			resetFrame()
			return true
		} isTargeted: { dropTargeted = $0 }
		.help("Drag to move, pinch or use the slider to zoom. Drop an image to use it as the cover.")
	}

	private var zoomControls: some View {
		HStack {
			Image(systemName: "minus.magnifyingglass").foregroundStyle(.secondary)
			Slider(value: $state.zoom, in: 1...4)
			Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary)
			Button("Fit") { resetFrame() }.disabled(!state.isAdjusted)
			Button("Fill") { fill() }
		}
		.disabled(state.image == nil || state.source == .none || state.source == .generated)
		.controlSize(.small)
	}

	private var sourcePicker: some View {
		VStack(alignment: .leading, spacing: 6) {
			let count = job.book?.illustrationCount ?? 0
			if count > missing.count {
				Text("Illustrations").font(.caption).foregroundStyle(.secondary)
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 6) {
						ForEach((0..<min(count, 60)).filter { !missing.contains($0) }, id: \.self) { i in
							thumb(i)
						}
					}
				}
				.frame(height: 66)
			}
			HStack {
				Button("Image…") { chooseFile() }
				Button("Make One") {
					state.source = .generated
					resetFrame()
				}
				.help("A simple cover with the title and author in vertical type")
				Button("None") {
					state.source = .none
					resetFrame()
				}
			}
			.controlSize(.small)
			if case .illustration = state.source, state.isAdjusted {
				@Bindable var model = model
				Toggle("Keep the original illustration in the book", isOn: $model.settings.replaceCover)
					.font(.caption)
			}
		}
	}

	private func thumb(_ i: Int) -> some View {
		Button {
			state.source = .illustration(i)
			state.image = thumbs[i]
			resetFrame()
			if thumbs[i] == nil { Task { state.image = await model.illustration(job, index: i) } }
		} label: {
			Group {
				if let t = thumbs[i] {
					Image(decorative: t, scale: 1).resizable().aspectRatio(contentMode: .fill)
				} else {
					Color.secondary.opacity(0.15)
				}
			}
			.frame(width: 46, height: 62)
			.clipShape(RoundedRectangle(cornerRadius: 3))
			.overlay(RoundedRectangle(cornerRadius: 3).stroke(state.source == .illustration(i) ? Washi.vermilion : .clear, lineWidth: 2.5))
		}
		.buttonStyle(.plain)
	}

	private var panGesture: some Gesture {
		DragGesture()
			.onChanged { v in
				let start = dragStart ?? state.offset
				if dragStart == nil { dragStart = start }
				state.offset = CGSize(width: start.width + v.translation.width, height: start.height + v.translation.height)
			}
			.onEnded { _ in dragStart = nil }
	}

	private var magnifyGesture: some Gesture {
		MagnifyGesture()
			.onChanged { v in
				let start = zoomStart ?? state.zoom
				if zoomStart == nil { zoomStart = start }
				state.zoom = min(4, max(1, start * v.magnification))
			}
			.onEnded { _ in zoomStart = nil }
	}

	private func resetFrame() {
		withAnimation(.spring(response: 0.3)) {
			state.zoom = 1
			state.offset = .zero
		}
	}

	/// Zoom so the image covers the whole frame.
	private func fill() {
		guard let image = state.image else { return }
		let W = CGFloat(image.width), H = CGFloat(image.height)
		let fit = min(state.frame.width / W, state.frame.height / H)
		let fillScale = max(state.frame.width / W, state.frame.height / H)
		withAnimation(.spring(response: 0.3)) {
			state.zoom = min(4, fillScale / fit)
			state.offset = .zero
		}
	}

	private func chooseFile() {
		let panel = NSOpenPanel()
		panel.allowedContentTypes = [.png, .jpeg, .gif]
		if panel.runModal() == .OK, let url = panel.url, let image = Self.load(url) {
			state.source = .file(url.path)
			state.image = image
			resetFrame()
		}
	}

	private func loadThumbs() async {
		let count = min(job.book?.illustrationCount ?? 0, 60)
		for i in 0..<count {
			if let image = await model.illustration(job, index: i) {
				thumbs[i] = image
				if case .illustration(let sel) = state.source, sel == i, state.image == nil { state.image = image }
			} else {
				missing.insert(i)
			}
		}
	}

	static func load(_ url: URL) -> CGImage? {
		guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
		return CGImageSourceCreateImageAtIndex(src, 0, nil)
	}
}
