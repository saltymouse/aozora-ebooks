import SwiftUI
import AozoraKit

/// A book standing on the shelf.
struct BookCard: View {
	@Environment(AppModel.self) private var model
	let job: BookJob
	var selected: Bool
	@State private var hovering = false
	@State private var showReason = false

	private let coverWidth: CGFloat = 132

	var body: some View {
		VStack(spacing: 10) {
			cover
				.overlay(alignment: .bottomTrailing) { badge.offset(x: 14, y: 10) }
				.frame(width: coverWidth, height: coverWidth * 4 / 3, alignment: .bottom)
				.scaleEffect(hovering ? 1.035 : 1, anchor: .bottom)
				.animation(.spring(response: 0.28, dampingFraction: 0.65), value: hovering)
				.onHover { hovering = $0 }
			VStack(spacing: 2) {
				Text(job.title)
					.font(.system(.callout, design: .serif).weight(.semibold))
					.lineLimit(2)
					.multilineTextAlignment(.center)
				Text(statusLine)
					.font(.caption)
					.foregroundStyle(statusColor)
					.lineLimit(1)
			}
			.frame(width: coverWidth + 16)
		}
		.padding(6)
		.background(RoundedRectangle(cornerRadius: 10).fill(selected ? Color.accentColor.opacity(0.14) : .clear))
		.contentShape(Rectangle())
		.onTapGesture(count: 2) { open() }
		.contextMenu { menu }
		.popover(isPresented: Binding(get: { showReason && job.phase == .skipped }, set: { showReason = $0 })) {
			ReasonPopover(job: job, close: { showReason = false })
		}
		.help(job.sourceDescription)
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(job.title), \(statusLine)")
	}

	@ViewBuilder private var cover: some View {
		Group {
			if let image = job.cover {
				Image(decorative: image, scale: 1)
					.resizable()
					.aspectRatio(contentMode: .fit)
			} else {
				GeneratedCover(title: job.title, author: job.author)
			}
		}
		.clipShape(RoundedRectangle(cornerRadius: 3))
		.overlay(alignment: .leading) {
			// a hint of a spine
			LinearGradient(colors: [.black.opacity(0.25), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 6)
		}
		.bookShadow()
		.overlay { activityOverlay }
		.saturation(job.phase == .skipped ? 0 : 1)
		.opacity(job.phase == .skipped ? 0.55 : 1)
	}

	@ViewBuilder private var activityOverlay: some View {
		switch job.phase {
		case .queued:
			Color.white.opacity(0.35)
		case .downloading, .reading:
			ZStack {
				Color.black.opacity(0.25)
				ProgressView().controlSize(.large).tint(.white)
			}
		case .converting(let p):
			ZStack {
				Color.black.opacity(0.3)
				ProgressRing(progress: p).frame(width: 46, height: 46)
			}
		case .review:
			ZStack {
				Color.black.opacity(0.2)
				Image(systemName: "eye.fill").font(.title).foregroundStyle(.white).symbolEffect(.pulse)
			}
		default:
			EmptyView()
		}
	}

	@ViewBuilder private var badge: some View {
		switch job.phase {
		case .done:
			HankoStamp()
		case .failed:
			Button { showReason = true } label: {
				Image(systemName: "exclamationmark.triangle.fill")
					.font(.title)
					.foregroundStyle(.white, .orange)
					.shadow(radius: 2)
			}
			.buttonStyle(.plain)
			.help(job.reason ?? "")
			.popover(isPresented: $showReason, arrowEdge: .trailing) { ReasonPopover(job: job, close: { showReason = false }) }
		default:
			if !job.warnings.isEmpty && job.phase.isFinished {
				Text("\(job.warnings.count)")
					.font(.caption2.bold())
					.padding(5)
					.background(Circle().fill(.orange))
					.foregroundStyle(.white)
			}
		}
	}

	private var statusLine: String {
		switch job.phase {
		case .queued: return String(localized: "Waiting…")
		case .downloading: return String(localized: "Downloading…")
		case .reading: return String(localized: "Reading…")
		case .review: return String(localized: "Ready for review")
		case .converting(let p): return String(localized: "Binding… \(Int(p * 100))%")
		case .done: return job.author.isEmpty ? String(localized: "Done") : job.author
		case .skipped: return job.reason == nil ? String(localized: "Skipped") : String(localized: "Skipped: click for why")
		case .failed: return String(localized: "Couldn't convert: click ⚠")
		}
	}

	private var statusColor: Color {
		switch job.phase {
		case .failed: return .orange
		case .done: return .secondary
		default: return .secondary
		}
	}

	private func open() {
		if let url = job.outputURL { NSWorkspace.shared.open(url) }
		else if case .review = job.phase { model.reviewing = job }
		else if job.reason != nil { showReason = true }
	}

	@ViewBuilder private var menu: some View {
		if let url = job.outputURL {
			Button("Open") { NSWorkspace.shared.open(url) }
			Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
			Button("Copy Path") {
				NSPasteboard.general.clearContents()
				NSPasteboard.general.setString(url.path, forType: .string)
			}
			Divider()
		}
		if case .file(let src) = job.source {
			Button("Show Original in Finder") { NSWorkspace.shared.activateFileViewerSelecting([src]) }
		}
		if case .web(let link) = job.source, let url = URL(string: link) {
			Button("Open Web Page") { NSWorkspace.shared.open(url) }
		}
		Button("Show Activity") {
			model.showLog = true
		}
		if job.phase.isFinished {
			Button("Convert Again") { model.retry(job) }
		}
		Divider()
		Button("Remove from Shelf", role: .destructive) { model.remove(job) }
			.disabled(job.phase.isActive || job.phase == .review)
	}
}

/// Circular progress in the app's vermilion.
struct ProgressRing: View {
	var progress: Double

	var body: some View {
		ZStack {
			Circle().stroke(.white.opacity(0.3), lineWidth: 5)
			Circle()
				.trim(from: 0, to: max(0.02, progress))
				.stroke(Washi.vermilion, style: StrokeStyle(lineWidth: 5, lineCap: .round))
				.rotationEffect(.degrees(-90))
				.animation(.easeOut(duration: 0.2), value: progress)
		}
	}
}

/// The full error (or skip reason) with ways to fix it.
struct ReasonPopover: View {
	@Environment(AppModel.self) private var model
	let job: BookJob
	var close: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			Label(job.phase == .skipped ? String(localized: "Skipped") : String(localized: "Couldn't convert “\(job.title)”"),
			      systemImage: job.phase == .skipped ? "forward.fill" : "exclamationmark.triangle.fill")
				.font(.headline)
				.foregroundStyle(job.phase == .skipped ? Color.secondary : Color.orange)
			Text(job.reason ?? String(localized: "No details."))
				.textSelection(.enabled)
				.fixedSize(horizontal: false, vertical: true)
			HStack {
				if job.isKindlegenError {
					Button("Make EPUB Instead") {
						model.makeEpubInstead()
						model.retry(job)
						close()
					}
					.buttonStyle(.borderedProminent)
				}
				Button("Try Again") {
					model.retry(job)
					close()
				}
				Spacer()
				Button("Show Activity") {
					model.showLog = true
					close()
				}
			}
		}
		.padding(16)
		.frame(width: 380)
	}
}
