import Foundation
import CArchive

/// Reads zip/cbz/txtz/rar archives through the system libarchive.
/// Zip names without the UTF-8 flag are decoded as CP932, as the Java app did.
struct ArchiveReader {
	struct Entry {
		let name: String
		let isDirectory: Bool
	}

	enum Failure: Error, CustomStringConvertible {
		case open(String)
		var description: String {
			switch self { case .open(let s): return "Could not open archive: \(s)" }
		}
	}

	let url: URL

	/// Visits every entry in archive order. Return false from `body` to stop.
	/// `readData` returns the entry's bytes; call it at most once per entry.
	func forEach(_ body: (Entry, () -> Data) throws -> Bool) throws {
		guard let a = archive_read_new() else { throw Failure.open(url.path) }
		defer { archive_read_free(a) }
		archive_read_support_format_all(a)
		archive_read_support_filter_all(a)
		_ = archive_read_set_options(a, "hdrcharset=CP932")
		guard archive_read_open_filename(a, url.path, 65536) == ARCHIVE_OK else {
			throw Failure.open(String(cString: archive_error_string(a)))
		}
		var entry: OpaquePointer?
		while true {
			let r = archive_read_next_header(a, &entry)
			if r == ARCHIVE_EOF { break }
			guard r == ARCHIVE_OK || r == ARCHIVE_WARN, let entry else { break }
			let raw = archive_entry_pathname_utf8(entry) ?? archive_entry_pathname(entry)
			let name = raw.map { String(cString: $0) }?.replacingOccurrences(of: "\\", with: "/") ?? ""
			let isDir = archive_entry_filetype(entry) == UInt32(AE_IFDIR) || name.hasSuffix("/")
			var consumed = false
			let readData = { () -> Data in
				consumed = true
				var data = Data()
				var buf = [UInt8](repeating: 0, count: 65536)
				while true {
					let n = archive_read_data(a, &buf, buf.count)
					if n <= 0 { break }
					data.append(buf, count: n)
				}
				return data
			}
			let keepGoing = try body(Entry(name: name, isDirectory: isDir), readData)
			if !consumed { archive_read_data_skip(a) }
			if !keepGoing { break }
		}
	}

	/// Data of the first entry matching `name`, or nil.
	func data(named name: String) throws -> Data? {
		var result: Data?
		try forEach { e, read in
			if e.name == name { result = read(); return false }
			return true
		}
		return result
	}

	/// Names of the .txt entries, in archive order.
	func textEntryNames() throws -> [String] {
		var names: [String] = []
		try forEach { e, _ in
			if !e.isDirectory && e.name.lowercased().hasSuffix(".txt") { names.append(e.name) }
			return true
		}
		return names
	}
}
