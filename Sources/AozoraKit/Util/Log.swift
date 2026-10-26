import Foundation

/// One line of conversion log output (port of `LogAppender`).
public struct LogEntry: Sendable, Hashable {
	public enum Level: String, Sendable { case info = "INFO", warn = "WARN", error = "ERROR", plain = "" }
	public var level: Level
	/// 1-based source line, if the message refers to one.
	public var line: Int?
	public var message: String
	public var detail: String?

	public init(level: Level, line: Int? = nil, message: String, detail: String? = nil) {
		self.level = level
		self.line = line
		self.message = message
		self.detail = detail
	}

	/// The entry formatted exactly as AozoraEpub3 prints it.
	public var text: String {
		var s = level == .plain ? "" : "[\(level.rawValue)] "
		s += message
		if let line { s += " (\(line))" }
		if let detail { s += " : \(detail)" }
		return s
	}
}

/// Collects log output. Every message also goes to `handler`, so the CLI can
/// print and the app can stream into its activity view.
public final class Log: @unchecked Sendable {
	private let lock = NSLock()
	private var pending = ""
	public private(set) var entries: [LogEntry] = []
	public var handler: (@Sendable (LogEntry) -> Void)?

	public init(handler: (@Sendable (LogEntry) -> Void)? = nil) {
		self.handler = handler
	}

	private func emit(_ e: LogEntry) {
		lock.lock(); entries.append(e); lock.unlock()
		handler?(e)
	}

	// Java line numbers are 0-based; LogAppender printed lineNum+1.
	func info(_ lineNum: Int, _ msg: String, _ desc: String? = nil) { emit(LogEntry(level: .info, line: lineNum + 1, message: msg, detail: desc)) }
	func warn(_ lineNum: Int, _ msg: String, _ desc: String? = nil) { emit(LogEntry(level: .warn, line: lineNum + 1, message: msg, detail: desc)) }
	func error(_ lineNum: Int, _ msg: String, _ desc: String? = nil) { emit(LogEntry(level: .error, line: lineNum + 1, message: msg, detail: desc)) }
	func error(_ msg: String) { emit(LogEntry(level: .error, line: nil, message: msg)) }
	func warn(_ msg: String) { emit(LogEntry(level: .warn, line: nil, message: msg)) }

	/// `LogAppender.println`
	public func println(_ msg: String = "") {
		lock.lock(); let line = pending + msg; pending = ""; lock.unlock()
		emit(LogEntry(level: .plain, line: nil, message: line))
	}
	/// `LogAppender.append` (buffered until the next println)
	func append(_ msg: String) {
		lock.lock(); pending += msg; lock.unlock()
	}

	public var warningCount: Int { entries.filter { $0.level == .warn }.count }
	public var errorCount: Int { entries.filter { $0.level == .error }.count }
}
