import SwiftUI
import AozoraKit

/// Conversion notes for the selected book (or all books).
struct LogView: View {
	@Environment(AppModel.self) private var model
	var job: BookJob?
	@State private var warningsOnly = true

	private var entries: [(BookJob, LogEntry)] {
		let jobs: [BookJob] = job.map { [$0] } ?? model.jobs
		var out: [(BookJob, LogEntry)] = []
		for j in jobs {
			for e in j.log {
				// the reason is already in the banner; don't repeat it in the list
				if e.line == nil && e.message == j.reason { continue }
				if warningsOnly && e.level != .warn && e.level != .error { continue }
				out.append((j, e))
			}
		}
		return out
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack {
				Text(job?.title ?? String(localized: "All Books")).font(.headline).lineLimit(1)
				Spacer()
				Toggle("Problems only", isOn: $warningsOnly).toggleStyle(.switch).controlSize(.mini)
			}
			.padding(12)
			Divider()
			// failed and skipped books always show their reason first, in full
			ForEach((job.map { [$0] } ?? model.jobs).filter { $0.reason != nil }) { j in
				ReasonBanner(job: j, showTitle: job == nil)
			}
			if entries.isEmpty {
				ContentUnavailableView(warningsOnly ? String(localized: "No other problems") : String(localized: "Nothing yet"),
				                       systemImage: warningsOnly ? "checkmark.seal" : "text.alignleft",
				                       description: warningsOnly ? Text("Notes about annotations the converter couldn't handle show up here.") : Text("Drop a book to get started."))
					.frame(maxHeight: 260)
			} else {
				ScrollView {
					LazyVStack(alignment: .leading, spacing: 6) {
						ForEach(Array(entries.enumerated()), id: \.offset) { _, pair in
							LogRow(entry: pair.1, bookTitle: job == nil ? pair.0.title : nil)
							Divider()
						}
					}
					.padding(12)
				}
			}
			Spacer(minLength: 0)
			Divider()
			HStack {
				Button("Copy All") {
					let text = entries.map { ($0.0.title + ": ") + $0.1.text }.joined(separator: "\n")
					NSPasteboard.general.clearContents()
					NSPasteboard.general.setString(text, forType: .string)
				}
				Spacer()
			}
			.controlSize(.small)
			.padding(10)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
	}
}

struct ReasonBanner: View {
	let job: BookJob
	var showTitle: Bool

	var body: some View {
		let failed = job.phase != .skipped
		HStack(alignment: .top, spacing: 8) {
			Image(systemName: failed ? "exclamationmark.triangle.fill" : "forward.fill")
				.foregroundStyle(failed ? .orange : .secondary)
			VStack(alignment: .leading, spacing: 4) {
				heading
					.font(.callout.bold())
				Text(job.reason ?? "")
					.font(.callout)
					.textSelection(.enabled)
					.lineLimit(nil)
					.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
		.padding(10)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(RoundedRectangle(cornerRadius: 8).fill((failed ? Color.orange : Color.secondary).opacity(0.12)))
		.padding(.horizontal, 10)
		.padding(.top, 8)
	}

	private var heading: Text {
		switch (showTitle, job.phase != .skipped) {
		case (true, true): Text("\(job.title): couldn't convert")
		case (true, false): Text("\(job.title): skipped")
		case (false, true): Text("Couldn't convert")
		case (false, false): Text("Skipped")
		}
	}
}

struct LogRow: View {
	let entry: LogEntry
	var bookTitle: String?

	var body: some View {
		HStack(alignment: .firstTextBaseline, spacing: 8) {
			Image(systemName: icon).foregroundStyle(color)
			VStack(alignment: .leading, spacing: 2) {
				HStack(spacing: 6) {
					if let line = entry.line, line > 0 { Text("line \(line)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
					if let bookTitle { Text(bookTitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
				}
				Text(LogGlossary.explain(entry.message) ?? entry.message).font(.callout)
				if let detail = entry.detail { Text(detail).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled) }
				if LogGlossary.explain(entry.message) != nil { Text(entry.message).font(.caption2).foregroundStyle(.tertiary) }
			}
		}
		.padding(.vertical, 2)
	}

	private var icon: String {
		switch entry.level {
		case .error: return "xmark.octagon.fill"
		case .warn: return "exclamationmark.triangle.fill"
		case .info: return "info.circle"
		case .plain: return "circle.fill"
		}
	}
	private var color: Color {
		switch entry.level {
		case .error: return .red
		case .warn: return .orange
		case .info: return .blue
		case .plain: return .secondary.opacity(0.4)
		}
	}
}

/// Plain-language versions of the converter's most common messages.
enum LogGlossary {
	static let table: [String: String] = [
		"注記未変換": "An annotation the converter doesn't support was left out",
		"外字未変換": "A rare character (gaiji) couldn't be converted and shows as 〓",
		"外字注記内に注記があります": "A gaiji note contains another note: fix the source text",
		"画像ファイルなし": "An illustration file referenced by the text is missing",
		"字下げ注記省略": "An indent block wasn't closed: it was closed automatically",
		"字下げ終わり重複": "An extra “end indent” annotation was ignored",
		"ルビが長すぎます": "Very long ruby text",
		"ルビ開始文字無し": "Ruby text with no base text",
		"コメントが閉じていません": "A comment block (-----) was never closed",
		"コメント開始行が10行目以降にあります": "The comment block starts late in the text",
		"注記内に注記があります": "An annotation is nested inside another",
		"割り注が長すぎます": "Very long inline note (warichu)",
		"タグが閉じていません": "A block wasn't closed before the page break",
		"拡張漢字出力": "A rare kanji outside the basic plane was kept (some readers can't show it)",
		"画像拡張子変更": "An illustration was found under a different file extension",
		"挿絵除外": "Illustration left out (Skip illustrations is on)",
		"画像の次の行にキャプションがありません": "An illustration expected a caption on the next line",
		"キャプションがあるため画像単ページ化されません": "Captioned illustrations stay inline instead of getting their own page",
	]

	static func explain(_ message: String) -> String? {
		// the converter's messages are already Japanese
		if Bundle.main.preferredLocalizations.first == "ja" { return nil }
		return table[message] ?? table.first { message.hasPrefix($0.key) }?.value
	}
}
