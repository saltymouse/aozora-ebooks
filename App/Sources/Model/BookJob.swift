import SwiftUI
import AozoraKit

/// One item on the shelf: a dropped file, a text inside an archive, or a web novel.
@MainActor @Observable
final class BookJob: Identifiable {
	enum Source: Equatable {
		case file(URL)
		case web(String)
	}

	enum Phase: Equatable {
		case queued
		case downloading
		case reading
		case review
		case converting(Double)
		case done(URL)
		case skipped
		case failed(String)

		var isFinished: Bool {
			switch self {
			case .done, .skipped, .failed: return true
			default: return false
			}
		}
		var isActive: Bool {
			switch self {
			case .downloading, .reading, .converting: return true
			default: return false
			}
		}
	}

	let id = UUID()
	let source: Source
	var phase: Phase = .queued
	var title: String
	var author = ""
	var cover: CGImage?
	var log: [LogEntry] = []
	/// Set once the file is scanned.
	var book: PreparedBook?
	/// Downloaded web text, converted as a file.
	var localFile: URL?

	init(source: Source) {
		self.source = source
		switch source {
		case .file(let url): title = url.deletingPathExtension().lastPathComponent
		case .web(let s): title = URL(string: s)?.host() ?? s
		}
	}

	var warnings: [LogEntry] { log.filter { $0.level == .warn || $0.level == .error } }

	/// Why the book failed or was skipped, in full.
	var reason: String? {
		switch phase {
		case .failed(let msg): return msg
		case .skipped: return skipReason
		default: return nil
		}
	}
	private(set) var skipReason: String?

	/// Marks the book failed and records the reason in its activity log.
	func fail(_ message: String) {
		phase = .failed(message)
		log.append(LogEntry(level: .error, line: nil, message: message))
	}

	/// Marks the book skipped; a reason (if any) goes to the activity log.
	func skip(_ reason: String? = nil) {
		skipReason = reason
		phase = .skipped
		if let reason { log.append(LogEntry(level: .warn, line: nil, message: reason)) }
	}

	var sourceDescription: String {
		switch source {
		case .file(let url): return url.lastPathComponent
		case .web(let s): return s
		}
	}

	var isKindlegenError: Bool { reason?.contains("kindlegen") == true }

	var outputURL: URL? {
		if case .done(let url) = phase { return url }
		return nil
	}
}
