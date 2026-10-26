import Foundation
import Synchronization

// The converter is a line-by-line port of AozoraEpub3 (Java). Java strings are
// UTF-16 and all of its index arithmetic is in UTF-16 code units, so these
// helpers expose String in the same terms. Keeping Java's semantics here is what
// lets the port produce byte-identical EPUB text.

/// A Java `char` (one UTF-16 code unit).
public typealias JChar = UInt16

// Lets `ch == "※"` and `case "※":` compile against UTF-16 code units.
extension UInt16: @retroactive ExpressibleByUnicodeScalarLiteral {
	public init(unicodeScalarLiteral value: Unicode.Scalar) {
		precondition(value.value <= 0xFFFF, "JChar literal outside the BMP")
		self = UInt16(value.value)
	}
}

extension String {
	/// Builds a String from UTF-16 code units (Java `new String(char[])`).
	init(jchars: some Collection<JChar>) {
		self = String(decoding: jchars, as: UTF16.self)
	}

	/// Java `length()`.
	var jlen: Int { utf16.count }

	/// Java `toCharArray()`.
	var jchars: [JChar] { Array(utf16) }

	/// Java `charAt(i)`. Out of range returns 0 where Java would throw: the app must not crash on odd input.
	func charAt(_ i: Int) -> JChar {
		guard i >= 0, i < jlen else { return 0 }
		return utf16[utf16.index(utf16.startIndex, offsetBy: i)]
	}

	/// Java `substring(begin)`.
	func jsub(_ begin: Int) -> String { jsub(begin, jlen) }

	/// Java `substring(begin, end)`.
	/// Out-of-range bounds are clamped where Java would throw.
	func jsub(_ beginIn: Int, _ endIn: Int) -> String {
		let n = jlen
		let end = min(max(endIn, 0), n)
		let begin = min(max(beginIn, 0), end)
		let u = utf16
		let s = u.index(u.startIndex, offsetBy: begin)
		let e = u.index(s, offsetBy: end - begin)
		return String(jchars: u[s..<e])
	}

	/// Java `indexOf(str, fromIndex)`.
	func indexOf(_ str: String, _ from: Int = 0) -> Int {
		let ns = self as NSString
		let len = ns.length
		let start = max(0, from)
		if start > len { return str.isEmpty ? len : -1 }
		if str.isEmpty { return start }
		let r = ns.range(of: str, options: .literal, range: NSRange(location: start, length: len - start))
		return r.location == NSNotFound ? -1 : r.location
	}

	/// Java `indexOf(char, fromIndex)`.
	func indexOf(_ ch: JChar, _ from: Int = 0) -> Int {
		var i = 0
		for c in utf16 {
			if i >= from && c == ch { return i }
			i += 1
		}
		return -1
	}

	/// Java `lastIndexOf(str, fromIndex)`.
	func lastIndexOf(_ str: String, _ from: Int = Int.max) -> Int {
		if from < 0 { return -1 }
		let ns = self as NSString
		let strLen = (str as NSString).length
		let end = min(ns.length, from == Int.max ? ns.length : from + strLen)
		if str.isEmpty { return min(from, ns.length) }
		if end <= 0 { return -1 }
		let r = ns.range(of: str, options: [.literal, .backwards], range: NSRange(location: 0, length: end))
		return r.location == NSNotFound ? -1 : r.location
	}

	/// Java `lastIndexOf(char, fromIndex)`.
	func lastIndexOf(_ ch: JChar, _ from: Int = Int.max) -> Int {
		let u = Array(utf16)
		var i = min(from, u.count - 1)
		while i >= 0 {
			if u[i] == ch { return i }
			i -= 1
		}
		return -1
	}

	/// Java `startsWith(prefix, offset)`.
	func startsWith(_ prefix: String, _ offset: Int = 0) -> Bool {
		if offset == 0 { return utf16.starts(with: prefix.utf16) }
		if offset < 0 || offset > jlen { return false }
		return utf16.dropFirst(offset).starts(with: prefix.utf16)
	}

	/// Java `endsWith(suffix)` compared by code units (no Unicode normalization).
	func endsWith(_ suffix: String) -> Bool {
		let a = utf16, b = suffix.utf16
		return a.count >= b.count && a.dropFirst(a.count - b.count).elementsEqual(b)
	}

	/// Java `equals` compared by code units (Swift `==` normalizes).
	func jequals(_ other: String?) -> Bool {
		guard let other else { return false }
		return utf16.elementsEqual(other.utf16)
	}

	/// Java `toLowerCase()`.
	func toLowerCase() -> String { lowercased() }

	/// Java `trim()`: strips chars <= U+0020 from both ends.
	func jtrim() -> String {
		let u = Array(utf16)
		var s = 0, e = u.count
		while s < e && u[s] <= 0x20 { s += 1 }
		while e > s && u[e - 1] <= 0x20 { e -= 1 }
		return String(jchars: u[s..<e])
	}

	/// Java `replace(char, char)`.
	func jreplace(_ a: JChar, _ b: JChar) -> String {
		String(jchars: utf16.map { $0 == a ? b : $0 })
	}

	// MARK: Regex (java.util.regex semantics over ICU)

	/// Java `replaceAll(regex, replacement)`.
	func replaceAll(_ regex: String, _ replacement: String) -> String {
		JPattern.compile(regex).matcher(self).replaceAll(replacement)
	}

	/// Java `replaceFirst(regex, replacement)`.
	func replaceFirst(_ regex: String, _ replacement: String) -> String {
		JPattern.compile(regex).matcher(self).replaceFirst(replacement)
	}

	/// Java `matches(regex)`: the whole string must match.
	func matches(_ regex: String) -> Bool {
		JPattern.compile(regex).matcher(self).matches()
	}

	/// Java `split(regex, limit)`: trailing empty strings are dropped when limit == 0.
	func split(regex: String, limit: Int = 0) -> [String] {
		let ns = self as NSString
		if ns.length == 0 { return [""] }
		let matches = JPattern.compile(regex).regex.matches(in: self, range: NSRange(location: 0, length: ns.length))
		var parts: [String] = []
		var index = 0
		for m in matches {
			if limit > 0 && parts.count == limit - 1 { break }
			// A zero-width match at the beginning never produces a leading empty substring.
			if m.range.location == 0 && m.range.length == 0 { continue }
			if m.range.length == 0 && m.range.location >= ns.length { continue }
			parts.append(ns.substring(with: NSRange(location: index, length: m.range.location - index)))
			index = m.range.location + m.range.length
		}
		if index == 0 && parts.isEmpty { return [self] }
		parts.append(ns.substring(from: index))
		if limit == 0 {
			while let last = parts.last, last.isEmpty { parts.removeLast() }
		}
		return parts
	}
}

// MARK: - StringBuilder

/// Java `StringBuilder`, backed by UTF-16 code units.
final class JBuilder {
	var u: [JChar]

	init() { u = [] }
	init(_ s: String) { u = Array(s.utf16) }

	var length: Int { u.count }
	func setLength(_ n: Int) {
		if n < u.count { u.removeSubrange(n...) } else if n > u.count { u.append(contentsOf: repeatElement(0, count: n - u.count)) }
	}
	// Bounds are clamped where Java would throw, so malformed input can't crash the app.
	func charAt(_ i: Int) -> JChar { i >= 0 && i < u.count ? u[i] : 0 }
	func setCharAt(_ i: Int, _ c: JChar) { if i >= 0 && i < u.count { u[i] = c } }

	@discardableResult func append(_ s: String) -> JBuilder { u.append(contentsOf: s.utf16); return self }
	@discardableResult func appendChar(_ c: JChar) -> JBuilder { u.append(c); return self }
	@discardableResult func append(_ b: JBuilder) -> JBuilder { u.append(contentsOf: b.u); return self }
	@discardableResult func append(_ i: Int) -> JBuilder { append(String(i)) }

	func insert(_ offset: Int, _ s: String) { u.insert(contentsOf: s.utf16, at: min(max(offset, 0), u.count)) }
	func delete(_ start: Int, _ end: Int) {
		let e = min(max(end, 0), u.count), b = min(max(start, 0), e)
		u.removeSubrange(b..<e)
	}
	func deleteCharAt(_ i: Int) { if i >= 0 && i < u.count { u.remove(at: i) } }

	func substring(_ start: Int, _ end: Int) -> String {
		let e = min(max(end, 0), u.count), b = min(max(start, 0), e)
		return String(jchars: u[b..<e])
	}

	func indexOf(_ s: String, _ from: Int = 0) -> Int { toString().indexOf(s, from) }
	func lastIndexOf(_ s: String, _ from: Int = Int.max) -> Int { toString().lastIndexOf(s, from) }

	func toString() -> String { String(jchars: u) }
}

// MARK: - Pattern / Matcher

/// Java `Pattern`, compiled once and cached.
final class JPattern: @unchecked Sendable {
	let regex: NSRegularExpression
	let pattern: String
	private let fullRegex: NSRegularExpression

	private static let cache = Mutex<[String: JPattern]>([:])

	private init(_ pattern: String, options: NSRegularExpression.Options) {
		self.pattern = pattern
		do {
			regex = try NSRegularExpression(pattern: pattern, options: options)
			fullRegex = try NSRegularExpression(pattern: "\\A(?:" + pattern + ")\\z", options: options)
		} catch {
			fatalError("Invalid regex \(pattern): \(error)")
		}
	}

	/// Compiles (or fetches) a pattern. Crashes on invalid syntax: only for patterns in our own source.
	static func compile(_ pattern: String, caseInsensitive: Bool = false) -> JPattern {
		let key = (caseInsensitive ? "i:" : "s:") + pattern
		return cache.withLock { cache in
			if let p = cache[key] { return p }
			let p = JPattern(pattern, options: caseInsensitive ? [.caseInsensitive] : [])
			cache[key] = p
			return p
		}
	}

	/// Compiles a user-supplied pattern, returning nil if it is invalid.
	static func tryCompile(_ pattern: String) -> JPattern? {
		guard (try? NSRegularExpression(pattern: pattern)) != nil,
		      (try? NSRegularExpression(pattern: "\\A(?:" + pattern + ")\\z")) != nil else { return nil }
		return compile(pattern)
	}

	func matcher(_ s: String) -> JMatcher { JMatcher(self, s) }

	fileprivate func fullMatch(_ s: String) -> Bool {
		fullRegex.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
	}
}

/// Java `Matcher`: iterate with `find()`, then read `group`, `start`, `end`.
final class JMatcher {
	private let pattern: JPattern
	private let input: String
	private let ns: NSString
	private var results: [NSTextCheckingResult]? = nil
	private var pos = -1

	fileprivate init(_ pattern: JPattern, _ input: String) {
		self.pattern = pattern
		self.input = input
		self.ns = input as NSString
	}

	private var all: [NSTextCheckingResult] {
		if let results { return results }
		let r = pattern.regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
		results = r
		return r
	}

	func find() -> Bool {
		pos += 1
		return pos < all.count
	}

	func matches() -> Bool { pattern.fullMatch(input) }

	private var current: NSTextCheckingResult { all[pos] }

	func group() -> String { ns.substring(with: current.range) }
	func group(_ n: Int) -> String? {
		let r = current.range(at: n)
		return r.location == NSNotFound ? nil : ns.substring(with: r)
	}
	func start() -> Int { current.range.location }
	func end() -> Int { current.range.location + current.range.length }

	func replaceAll(_ template: String) -> String {
		pattern.regex.stringByReplacingMatches(in: input, range: NSRange(location: 0, length: ns.length), withTemplate: template)
	}

	func replaceFirst(_ template: String) -> String {
		guard let m = pattern.regex.firstMatch(in: input, range: NSRange(location: 0, length: ns.length)) else { return input }
		let replacement = pattern.regex.replacementString(for: m, in: input, offset: 0, template: template)
		return ns.replacingCharacters(in: m.range, with: replacement)
	}
}

// MARK: - Formatting

/// Java `String.valueOf(double)` (`Double.toString`).
func javaString(_ d: Double) -> String {
	if d.isNaN { return "NaN" }
	if d.isInfinite { return d < 0 ? "-Infinity" : "Infinity" }
	if d == 0 { return d.sign == .minus ? "-0.0" : "0.0" }
	let a = abs(d)
	if a >= 1e-3 && a < 1e7 {
		var s = "\(d)"
		if !s.contains(".") { s += ".0" }
		return s
	}
	// Java computerized scientific notation: 1.0E7, 1.234E-5
	var exponent = Int(floor(log10(a)))
	var mantissa = d / pow(10, Double(exponent))
	if abs(mantissa) >= 10 { mantissa /= 10; exponent += 1 }
	var m = "\(mantissa)"
	if !m.contains(".") { m += ".0" }
	return m + "E" + String(exponent)
}

/// Java `String.valueOf(float)` (`Float.toString`).
func javaString(_ f: Float) -> String {
	if f.isNaN { return "NaN" }
	if f.isInfinite { return f < 0 ? "-Infinity" : "Infinity" }
	let a = abs(f)
	if a >= 1e-3 && a < 1e7 {
		var s = "\(f)"
		if !s.contains(".") { s += ".0" }
		return s
	}
	return javaString(Double("\(f)") ?? Double(f))
}

/// Java `String.format` for the subset the chuki tables use: `%s` and `%%`.
func javaFormat(_ format: String, _ args: Any...) -> String {
	var out = ""
	var argIndex = 0
	var it = format.makeIterator()
	while let c = it.next() {
		guard c == "%" else { out.append(c); continue }
		guard let spec = it.next() else { out.append(c); break }
		switch spec {
		case "%": out.append("%")
		case "s":
			let arg = argIndex < args.count ? args[argIndex] : "null"
			argIndex += 1
			switch arg {
			case let d as Double: out += javaString(d)
			case let f as Float: out += javaString(f)
			default: out += "\(arg)"
			}
		default:
			out.append(c); out.append(spec)
		}
	}
	return out
}

/// Java `Integer.toHexString`.
func hex(_ v: Int) -> String { String(v, radix: 16) }

/// Java `Integer.parseInt` that throws away failures the way the Java call sites do with try/catch.
func parseInt(_ s: String?) -> Int? {
	guard let s else { return nil }
	return Int(s)
}
