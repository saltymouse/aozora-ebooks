import Foundation

// A small interpreter for the subset of Apache Velocity 1.7 that the AozoraEpub3
// templates use, so the original .vm files (and users' customized copies) keep working:
//   ${ref} $ref ${a.b.c} $a[0] ${s.length()}   references, properties, index, length()
//   #if / #elseif / #else / #end               with == != < > <= >= && || ! + - * / %
//   #foreach($x in $list) … #break … #end      with $velocityCount
//   #set($x = expr)                            ## line comments
// Whitespace follows Velocity 1.7: a directive alone on its line consumes that line's newline.

/// A value in the template context.
public indirect enum VValue {
	case undefined
	case null
	case string(String)
	case int(Int)
	case double(Double)
	case float(Float)
	case bool(Bool)
	case list([VValue])
	case object(VelocityObject)

	static func from(_ s: String?) -> VValue { s.map { .string($0) } ?? .null }

	var isTruthy: Bool {
		switch self {
		case .undefined, .null: return false
		case .bool(let b): return b
		default: return true // Velocity 1.7: any non-null, non-boolean value (even "") is true
		}
	}

	var number: Double? {
		switch self {
		case .int(let i): return Double(i)
		case .double(let d): return d
		case .float(let f): return Double(f)
		default: return nil
		}
	}

	/// Java toString() of the value.
	var rendered: String? {
		switch self {
		case .undefined, .null: return nil
		case .string(let s): return s
		case .int(let i): return String(i)
		case .double(let d): return javaString(d)
		case .float(let f): return javaString(f)
		case .bool(let b): return b ? "true" : "false"
		case .list(let l): return "[" + l.map { $0.rendered ?? "null" }.joined(separator: ", ") + "]"
		case .object: return "\(self)"
		}
	}
}

/// Objects exposing bean properties to templates. Names arrive lowercased
/// (Velocity resolves `ChapterName`, `chapterName` and `isChapterName` alike).
public protocol VelocityObject: AnyObject {
	func vproperty(_ name: String) -> VValue
}

/// Template variables.
final class VelocityContext {
	var values: [String: VValue] = [:]
	subscript(_ key: String) -> VValue {
		get { values[key] ?? .undefined }
		set { values[key] = newValue }
	}
	func put(_ key: String, _ s: String?) { values[key] = .from(s) }
	func put(_ key: String, _ b: Bool) { values[key] = .bool(b) }
	func put(_ key: String, _ i: Int) { values[key] = .int(i) }
	func put(_ key: String, _ o: VelocityObject?) { values[key] = o.map { .object($0) } ?? .null }
	func put(_ key: String, _ l: [VelocityObject]) { values[key] = .list(l.map { .object($0) }) }
}

// MARK: - AST

private indirect enum Node {
	case text(String)
	/// literal: the source text echoed when the reference is undefined
	case ref(Expr, literal: String, quiet: Bool)
	case ifBlock([(Expr, [Node])], else: [Node]?)
	case foreach(variable: String, Expr, [Node])
	case set(String, Expr)
	case breakLoop
}

private indirect enum Expr {
	case ref(name: String, path: [Accessor])
	case string(String)
	case number(Double, isInt: Bool)
	case bool(Bool)
	case not(Expr)
	case binary(String, Expr, Expr)
}

private enum Accessor {
	case property(String)
	case index(Expr)
	case method(String)
}

// MARK: - Template

final class VelocityTemplate {
	private let nodes: [Node]

	init(_ source: String) throws {
		var p = Parser(source)
		nodes = try p.parseNodes(until: [])
	}

	convenience init(contentsOf url: URL) throws {
		try self.init(String(decoding: try Data(contentsOf: url), as: UTF8.self))
	}

	func render(_ context: VelocityContext) -> String {
		var out = ""
		var locals = context.values
		_ = Renderer.run(nodes, &locals, &out)
		return out
	}
}

struct VelocityError: Error, CustomStringConvertible {
	var description: String
}

// MARK: - Parser

private struct Parser {
	// Unicode scalars, not Characters: "\r\n" must stay two units for newline handling.
	let s: [Unicode.Scalar]
	var i = 0

	init(_ source: String) { s = Array(source.unicodeScalars) }

	var atEnd: Bool { i >= s.count }
	func peek(_ o: Int = 0) -> Unicode.Scalar? { i + o < s.count ? s[i + o] : nil }

	/// True if position p starts a line (only spaces/tabs before it on the line).
	func lineStartBefore(_ p: Int) -> Bool {
		var k = p - 1
		while k >= 0 {
			if s[k] == "\n" { return true }
			if s[k] != " " && s[k] != "\t" { return false }
			k -= 1
		}
		return true
	}

	/// After a directive: if only whitespace remains on the line, consume through the newline.
	mutating func gobbleLine(directiveStart: Int, text: inout [Node]) {
		var k = i
		while k < s.count && (s[k] == " " || s[k] == "\t") { k += 1 }
		if k < s.count && s[k] == "\n" && lineStartBefore(directiveStart) {
			i = k + 1
		} else if k < s.count && s[k] == "\r" && k + 1 < s.count && s[k + 1] == "\n" && lineStartBefore(directiveStart) {
			i = k + 2
		}
	}

	mutating func parseNodes(until terminators: Set<String>) throws -> [Node] {
		var nodes: [Node] = []
		var text = String.UnicodeScalarView()
		func flush() { if !text.isEmpty { nodes.append(.text(String(text))); text = String.UnicodeScalarView() } }

		while !atEnd {
			let c = s[i]
			if c == "#" {
				// ## comment: drop to end of line, including the newline
				if peek(1) == "#" {
					flush()
					while !atEnd && s[i] != "\n" { i += 1 }
					if !atEnd { i += 1 }
					continue
				}
				let start = i
				if let name = directiveName() {
					if terminators.contains(name) {
						flush()
						return nodes
					}
					switch name {
					case "if":
						flush()
						i = start + 1 + name.count
						let cond = try parseParenExpr()
						var trailing: [Node] = []
						gobbleLine(directiveStart: start, text: &trailing)
						var branches: [(Expr, [Node])] = []
						var elseNodes: [Node]? = nil
						var body = try parseNodes(until: ["elseif", "else", "end"])
						var currentCond = cond
						while true {
							guard let term = directiveName() else { throw VelocityError(description: "unterminated #if") }
							let tStart = i
							i += 1 + term.count
							if term == "elseif" {
								branches.append((currentCond, body))
								currentCond = try parseParenExpr()
								gobbleLine(directiveStart: tStart, text: &trailing)
								body = try parseNodes(until: ["elseif", "else", "end"])
							} else if term == "else" {
								branches.append((currentCond, body))
								skipBraces()
								gobbleLine(directiveStart: tStart, text: &trailing)
								elseNodes = try parseNodes(until: ["end"])
								guard directiveName() == "end" else { throw VelocityError(description: "#else without #end") }
								let eStart = i
								i += 4
								skipBraces()
								gobbleLine(directiveStart: eStart, text: &trailing)
								break
							} else {
								branches.append((currentCond, body))
								skipBraces()
								gobbleLine(directiveStart: tStart, text: &trailing)
								break
							}
						}
						nodes.append(.ifBlock(branches, else: elseNodes))
						continue
					case "foreach":
						flush()
						i = start + 1 + name.count
						skipSpaces()
						guard peek() == "(" else { throw VelocityError(description: "#foreach without (") }
						i += 1
						skipSpaces()
						let variable = try parseVarName()
						skipSpaces()
						guard peek() == "i", peek(1) == "n" else { throw VelocityError(description: "#foreach missing in") }
						i += 2
						let listExpr = try parseExpr()
						skipSpaces()
						guard peek() == ")" else { throw VelocityError(description: "#foreach missing )") }
						i += 1
						var trailing: [Node] = []
						gobbleLine(directiveStart: start, text: &trailing)
						let body = try parseNodes(until: ["end"])
						guard directiveName() == "end" else { throw VelocityError(description: "#foreach without #end") }
						let eStart = i
						i += 4
						skipBraces()
						gobbleLine(directiveStart: eStart, text: &trailing)
						nodes.append(.foreach(variable: variable, listExpr, body))
						continue
					case "set":
						flush()
						i = start + 1 + name.count
						skipSpaces()
						guard peek() == "(" else { throw VelocityError(description: "#set without (") }
						i += 1
						skipSpaces()
						let variable = try parseVarName()
						skipSpaces()
						guard peek() == "=" else { throw VelocityError(description: "#set without =") }
						i += 1
						let value = try parseExpr()
						skipSpaces()
						guard peek() == ")" else { throw VelocityError(description: "#set missing )") }
						i += 1
						var trailing: [Node] = []
						gobbleLine(directiveStart: start, text: &trailing)
						nodes.append(.set(variable, value))
						continue
					case "break":
						flush()
						i = start + 1 + name.count
						skipBraces()
						var trailing: [Node] = []
						gobbleLine(directiveStart: start, text: &trailing)
						nodes.append(.breakLoop)
						continue
					default:
						break
					}
				}
				text.append(c)
				i += 1
				continue
			}
			if c == "$" {
				let start = i
				if let (expr, quiet) = tryParseReference() {
					flush()
					nodes.append(.ref(expr, literal: String(String.UnicodeScalarView(s[start..<i])), quiet: quiet))
					continue
				}
				i = start
			}
			text.append(c)
			i += 1
		}
		flush()
		if !terminators.isEmpty { throw VelocityError(description: "missing #end") }
		return nodes
	}

	/// Directive name at i (without consuming), handling #{else} forms.
	func directiveName() -> String? {
		guard peek() == "#" else { return nil }
		var k = i + 1
		if k < s.count && s[k] == "{" { k += 1 }
		var name = ""
		while k < s.count, s[k].isLetter { name.unicodeScalars.append(s[k]); k += 1 }
		switch name {
		case "if", "elseif", "else", "end", "foreach", "set", "break": return name
		default: return nil
		}
	}

	mutating func skipBraces() {
		if peek() == "}" { i += 1 }
	}

	mutating func skipSpaces() {
		while let c = peek(), c == " " || c == "\t" || c == "\n" || c == "\r" { i += 1 }
	}

	mutating func parseVarName() throws -> String {
		guard peek() == "$" else { throw VelocityError(description: "expected $variable") }
		i += 1
		let braced = peek() == "{"
		if braced { i += 1 }
		var name = ""
		while let c = peek(), c.isLetter || c.isNumber || c == "_" || c == "-" { name.unicodeScalars.append(c); i += 1 }
		if braced { guard peek() == "}" else { throw VelocityError(description: "expected }") }; i += 1 }
		return name
	}

	mutating func parseParenExpr() throws -> Expr {
		skipSpaces()
		guard peek() == "(" else { throw VelocityError(description: "expected (") }
		i += 1
		let e = try parseExpr()
		skipSpaces()
		guard peek() == ")" else { throw VelocityError(description: "expected )") }
		i += 1
		return e
	}

	/// $name, $!name, ${name}, $name.prop.method(), $name[expr]
	mutating func tryParseReference() -> (Expr, Bool)? {
		guard peek() == "$" else { return nil }
		var k = i + 1
		var quiet = false
		if k < s.count && s[k] == "!" { quiet = true; k += 1 }
		let braced = k < s.count && s[k] == "{"
		if braced { k += 1 }
		guard k < s.count, s[k].isLetter || s[k] == "_" else { return nil }
		var name = ""
		while k < s.count, s[k].isLetter || s[k].isNumber || s[k] == "_" || s[k] == "-" {
			// a trailing '-' is not part of a name ("$a-1")
			if s[k] == "-" && !(k + 1 < s.count && (s[k + 1].isLetter || s[k + 1].isNumber)) { break }
			name.unicodeScalars.append(s[k]); k += 1
		}
		var path: [Accessor] = []
		while k < s.count {
			if s[k] == ".", k + 1 < s.count, s[k + 1].isLetter {
				k += 1
				var prop = ""
				while k < s.count, s[k].isLetter || s[k].isNumber || s[k] == "_" { prop.unicodeScalars.append(s[k]); k += 1 }
				if k + 1 < s.count && s[k] == "(" && s[k + 1] == ")" {
					k += 2
					path.append(.method(prop))
				} else {
					path.append(.property(prop))
				}
			} else if s[k] == "[" {
				var sub = Parser(String(String.UnicodeScalarView(s[(k + 1)...])))
				guard let e = try? sub.parseExpr() else { break }
				sub.skipSpaces()
				guard sub.peek() == "]" else { break }
				k = k + 1 + sub.i + 1
				path.append(.index(e))
			} else {
				break
			}
		}
		if braced {
			guard k < s.count, s[k] == "}" else { return nil }
			k += 1
		}
		i = k
		return (.ref(name: name, path: path), quiet)
	}

	// Expression grammar: or -> and -> not -> comparison -> additive -> multiplicative -> primary
	mutating func parseExpr() throws -> Expr { try parseOr() }

	mutating func parseOr() throws -> Expr {
		var lhs = try parseAnd()
		while true {
			skipSpaces()
			if peek() == "|" && peek(1) == "|" { i += 2; lhs = .binary("||", lhs, try parseAnd()) }
			else if matchWord("or") { lhs = .binary("||", lhs, try parseAnd()) }
			else { return lhs }
		}
	}

	mutating func parseAnd() throws -> Expr {
		var lhs = try parseNot()
		while true {
			skipSpaces()
			if peek() == "&" && peek(1) == "&" { i += 2; lhs = .binary("&&", lhs, try parseNot()) }
			else if matchWord("and") { lhs = .binary("&&", lhs, try parseNot()) }
			else { return lhs }
		}
	}

	mutating func parseNot() throws -> Expr {
		skipSpaces()
		if peek() == "!" && peek(1) != "=" { i += 1; return .not(try parseNot()) }
		if matchWord("not") { return .not(try parseNot()) }
		return try parseComparison()
	}

	mutating func parseComparison() throws -> Expr {
		let lhs = try parseAdditive()
		skipSpaces()
		for op in ["==", "!=", "<=", ">=", "<", ">"] where match(op) {
			return .binary(op, lhs, try parseAdditive())
		}
		for (word, op) in [("eq", "=="), ("ne", "!="), ("le", "<="), ("ge", ">="), ("lt", "<"), ("gt", ">")] where matchWord(word) {
			return .binary(op, lhs, try parseAdditive())
		}
		return lhs
	}

	mutating func parseAdditive() throws -> Expr {
		var lhs = try parseMultiplicative()
		while true {
			skipSpaces()
			if peek() == "+" { i += 1; lhs = .binary("+", lhs, try parseMultiplicative()) }
			else if peek() == "-" { i += 1; lhs = .binary("-", lhs, try parseMultiplicative()) }
			else { return lhs }
		}
	}

	mutating func parseMultiplicative() throws -> Expr {
		var lhs = try parsePrimary()
		while true {
			skipSpaces()
			if let c = peek(), c == "*" || c == "/" || c == "%" {
				i += 1
				lhs = .binary(String(Character(c)), lhs, try parsePrimary())
			} else { return lhs }
		}
	}

	mutating func parsePrimary() throws -> Expr {
		skipSpaces()
		guard let c = peek() else { throw VelocityError(description: "unexpected end of expression") }
		if c == "(" {
			i += 1
			let e = try parseExpr()
			skipSpaces()
			guard peek() == ")" else { throw VelocityError(description: "expected )") }
			i += 1
			return e
		}
		if c == "$" {
			guard let (e, _) = tryParseReference() else { throw VelocityError(description: "bad reference") }
			return e
		}
		if c == "\"" || c == "'" {
			i += 1
			var str = String.UnicodeScalarView()
			while let d = peek(), d != c { str.append(d); i += 1 }
			i += 1
			return .string(String(str))
		}
		if c.isNumber || (c == "-" && peek(1)?.isNumber == true) {
			var num = String(Character(c))
			i += 1
			while let d = peek(), d.isNumber || d == "." { num.unicodeScalars.append(d); i += 1 }
			return .number(Double(num) ?? 0, isInt: !num.contains("."))
		}
		if matchWord("true") { return .bool(true) }
		if matchWord("false") { return .bool(false) }
		throw VelocityError(description: "unexpected '\(Character(c))' in expression")
	}

	mutating func match(_ op: String) -> Bool {
		let chars = Array(op.unicodeScalars)
		for (o, ch) in chars.enumerated() where peek(o) != ch { return false }
		i += chars.count
		return true
	}

	mutating func matchWord(_ w: String) -> Bool {
		let chars = Array(w.unicodeScalars)
		for (o, ch) in chars.enumerated() where peek(o) != ch { return false }
		if let next = peek(chars.count), next.isLetter || next.isNumber { return false }
		i += chars.count
		return true
	}
}

// MARK: - Renderer

private enum Renderer {
	enum Flow { case normal, breakLoop }

	static func run(_ nodes: [Node], _ vars: inout [String: VValue], _ out: inout String) -> Flow {
		for node in nodes {
			switch node {
			case .text(let t):
				out += t
			case .ref(let e, let literal, let quiet):
				let v = eval(e, &vars)
				if let r = v.rendered { out += r } else if !quiet { out += literal }
			case .ifBlock(let branches, let elseNodes):
				var taken = false
				for (cond, body) in branches where eval(cond, &vars).isTruthy {
					taken = true
					if run(body, &vars, &out) == .breakLoop { return .breakLoop }
					break
				}
				if !taken, let elseNodes {
					if run(elseNodes, &vars, &out) == .breakLoop { return .breakLoop }
				}
			case .foreach(let variable, let listExpr, let body):
				let list: [VValue]
				switch eval(listExpr, &vars) {
				case .list(let l): list = l
				default: list = []
				}
				let savedVar = vars[variable]
				let savedCount = vars["velocityCount"]
				for (n, item) in list.enumerated() {
					vars[variable] = item
					vars["velocityCount"] = .int(n + 1)
					if run(body, &vars, &out) == .breakLoop { break }
				}
				vars[variable] = savedVar
				vars["velocityCount"] = savedCount
			case .set(let variable, let e):
				vars[variable] = eval(e, &vars)
			case .breakLoop:
				return .breakLoop
			}
		}
		return .normal
	}

	static func eval(_ e: Expr, _ vars: inout [String: VValue]) -> VValue {
		switch e {
		case .string(let s): return .string(s)
		case .number(let d, let isInt): return isInt ? .int(Int(d)) : .double(d)
		case .bool(let b): return .bool(b)
		case .not(let x): return .bool(!eval(x, &vars).isTruthy)
		case .ref(let name, let path):
			var v = vars[name] ?? .undefined
			for acc in path {
				switch (acc, v) {
				case (.property(let p), .object(let o)):
					v = o.vproperty(p.lowercased())
					if case .undefined = v, p.lowercased().hasPrefix("is") { v = o.vproperty(String(p.lowercased().dropFirst(2))) }
				case (.method(let m), .string(let s)) where m == "length":
					v = .int(s.jlen)
				case (.method(let m), .object(let o)):
					var name = m.lowercased()
					if name.hasPrefix("get") { name = String(name.dropFirst(3)) } else if name.hasPrefix("is") { name = String(name.dropFirst(2)) }
					v = o.vproperty(name)
				case (.index(let ie), .list(let l)):
					if let n = eval(ie, &vars).number, Int(n) >= 0, Int(n) < l.count { v = l[Int(n)] } else { v = .null }
				default:
					return .undefined
				}
			}
			return v
		case .binary(let op, let l, let r):
			switch op {
			case "&&": return .bool(eval(l, &vars).isTruthy && eval(r, &vars).isTruthy)
			case "||": return .bool(eval(l, &vars).isTruthy || eval(r, &vars).isTruthy)
			default: break
			}
			let a = eval(l, &vars), b = eval(r, &vars)
			if op == "==" || op == "!=" {
				let eq: Bool
				if let x = a.number, let y = b.number { eq = x == y }
				else { eq = a.rendered.map { ra in b.rendered.map { ra.jequals($0) } ?? false } ?? (b.rendered == nil) }
				return .bool(op == "==" ? eq : !eq)
			}
			guard let x = a.number, let y = b.number else {
				if op == "+", let ra = a.rendered, let rb = b.rendered { return .string(ra + rb) }
				return .null
			}
			let bothInt: Bool = { if case .int = a, case .int = b { return true }; return false }()
			switch op {
			case "<": return .bool(x < y)
			case ">": return .bool(x > y)
			case "<=": return .bool(x <= y)
			case ">=": return .bool(x >= y)
			case "+": return bothInt ? .int(Int(x) + Int(y)) : .double(x + y)
			case "-": return bothInt ? .int(Int(x) - Int(y)) : .double(x - y)
			case "*": return bothInt ? .int(Int(x) * Int(y)) : .double(x * y)
			case "/": return bothInt ? (y == 0 ? .null : .int(Int(x) / Int(y))) : .double(x / y)
			case "%": return bothInt ? (y == 0 ? .null : .int(Int(x) % Int(y))) : .double(x.truncatingRemainder(dividingBy: y))
			default: return .null
			}
		}
	}
}

private extension Unicode.Scalar {
	var isLetter: Bool { properties.isAlphabetic }
	var isNumber: Bool { ("0"..."9").contains(self) }
}
