import Foundation

/// A JSON value that round-trips losslessly: object key order is preserved and numbers are written in
/// their shortest form, so data written by the web app comes back out unchanged unless we edit it.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)

    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var doubleValue: Double? { if case .number(let n) = self { return n }; return nil }
    public var intValue: Int? { if case .number(let n) = self, n.rounded() == n, abs(n) < 9e15 { return Int(n) }; return nil }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var arrayValue: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    public var objectValue: JSONObject? { if case .object(let o) = self { return o }; return nil }
}

/// An insertion-ordered JSON object.
public struct JSONObject: Equatable, Sendable {
    public private(set) var keys: [String] = []
    private var storage: [String: JSONValue] = [:]

    public init() {}
    public init(_ pairs: [(String, JSONValue)]) { for (k, v) in pairs { self[k] = v } }

    public subscript(key: String) -> JSONValue? {
        get { storage[key] }
        set {
            if let v = newValue {
                if storage[key] == nil { keys.append(key) }
                storage[key] = v
            } else if storage.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }
    public var count: Int { keys.count }
    public var pairs: [(String, JSONValue)] { keys.map { ($0, storage[$0]!) } }

    public static func == (a: JSONObject, b: JSONObject) -> Bool { a.storage == b.storage }
}

public enum JSONError: Error, Equatable { case invalid(String, offset: Int) }

// MARK: - Parsing

public enum JSON {
    public static func parse(_ text: String) throws -> JSONValue {
        var p = Parser(Array(text.utf8))
        p.skipWS()
        let v = try p.value()
        p.skipWS()
        if p.i != p.b.count { throw JSONError.invalid("trailing characters", offset: p.i) }
        return v
    }
    public static func parse(_ data: Data) throws -> JSONValue {
        guard let s = String(data: data, encoding: .utf8) else { throw JSONError.invalid("not UTF-8", offset: 0) }
        return try parse(s)
    }

    /// Compact output (what the apps store in the Gist).
    public static func serialize(_ v: JSONValue) -> String {
        var out = ""
        out.reserveCapacity(1 << 16)
        write(v, into: &out)
        return out
    }

    static func write(_ v: JSONValue, into out: inout String) {
        switch v {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += formatNumber(n)
        case .string(let s): writeString(s, into: &out)
        case .array(let a):
            out += "["
            for (i, e) in a.enumerated() { if i > 0 { out += "," }; write(e, into: &out) }
            out += "]"
        case .object(let o):
            out += "{"
            for (i, (k, e)) in o.pairs.enumerated() {
                if i > 0 { out += "," }
                writeString(k, into: &out); out += ":"; write(e, into: &out)
            }
            out += "}"
        }
    }

    /// Same output as JavaScript's JSON.stringify for finite numbers in the ranges money and timestamps use.
    public static func formatNumber(_ n: Double) -> String {
        guard n.isFinite else { return "null" }
        if n == n.rounded() && abs(n) < 1e21 {
            if abs(n) < 9.007199254740992e15 { return String(Int64(n)) }
        }
        var s = "\(n)"           // Swift prints the shortest round-tripping form, like JS
        if s.hasSuffix(".0") { s.removeLast(2) }
        if let e = s.firstIndex(of: "e") {  // 1e-05 -> 1e-5 (JS style)
            let mant = s[..<e], exp = s[s.index(after: e)...]
            let sign = exp.hasPrefix("-") ? "-" : "+"
            let digits = exp.drop { $0 == "-" || $0 == "+" }.drop { $0 == "0" }
            s = "\(mant)e\(sign)\(digits.isEmpty ? "0" : String(digits))"
        }
        return s
    }

    static func writeString(_ s: String, into out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) }
                else { out.unicodeScalars.append(u) }
            }
        }
        out += "\""
    }

    struct Parser {
        let b: [UInt8]
        var i = 0
        init(_ b: [UInt8]) { self.b = b }

        mutating func skipWS() { while i < b.count, b[i] == 0x20 || b[i] == 0x0A || b[i] == 0x0D || b[i] == 0x09 { i += 1 } }

        mutating func value() throws -> JSONValue {
            guard i < b.count else { throw JSONError.invalid("unexpected end", offset: i) }
            switch b[i] {
            case UInt8(ascii: "{"): return .object(try object())
            case UInt8(ascii: "["): return .array(try array())
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try literal("true"); return .bool(true)
            case UInt8(ascii: "f"): try literal("false"); return .bool(false)
            case UInt8(ascii: "n"): try literal("null"); return .null
            default: return .number(try number())
            }
        }
        mutating func literal(_ s: String) throws {
            let u = Array(s.utf8)
            guard i + u.count <= b.count, Array(b[i..<i + u.count]) == u else { throw JSONError.invalid("bad literal", offset: i) }
            i += u.count
        }
        mutating func object() throws -> JSONObject {
            var o = JSONObject()
            i += 1; skipWS()
            if i < b.count, b[i] == UInt8(ascii: "}") { i += 1; return o }
            while true {
                skipWS()
                guard i < b.count, b[i] == UInt8(ascii: "\"") else { throw JSONError.invalid("expected key", offset: i) }
                let k = try string()
                skipWS()
                guard i < b.count, b[i] == UInt8(ascii: ":") else { throw JSONError.invalid("expected :", offset: i) }
                i += 1; skipWS()
                o[k] = try value()
                skipWS()
                guard i < b.count else { throw JSONError.invalid("unexpected end", offset: i) }
                if b[i] == UInt8(ascii: ",") { i += 1; continue }
                if b[i] == UInt8(ascii: "}") { i += 1; return o }
                throw JSONError.invalid("expected , or }", offset: i)
            }
        }
        mutating func array() throws -> [JSONValue] {
            var a: [JSONValue] = []
            i += 1; skipWS()
            if i < b.count, b[i] == UInt8(ascii: "]") { i += 1; return a }
            while true {
                skipWS()
                a.append(try value())
                skipWS()
                guard i < b.count else { throw JSONError.invalid("unexpected end", offset: i) }
                if b[i] == UInt8(ascii: ",") { i += 1; continue }
                if b[i] == UInt8(ascii: "]") { i += 1; return a }
                throw JSONError.invalid("expected , or ]", offset: i)
            }
        }
        mutating func hex4() throws -> UInt32 {
            guard i + 4 <= b.count, let v = UInt32(String(decoding: b[i..<i + 4], as: UTF8.self), radix: 16) else { throw JSONError.invalid("bad \\u escape", offset: i) }
            i += 4
            return v
        }
        mutating func string() throws -> String {
            i += 1
            var bytes: [UInt8] = []
            while true {
                guard i < b.count else { throw JSONError.invalid("unterminated string", offset: i) }
                let c = b[i]
                if c == UInt8(ascii: "\"") { i += 1; break }
                if c == UInt8(ascii: "\\") {
                    i += 1
                    guard i < b.count else { throw JSONError.invalid("bad escape", offset: i) }
                    let e = b[i]; i += 1
                    switch e {
                    case UInt8(ascii: "\""): bytes.append(0x22)
                    case UInt8(ascii: "\\"): bytes.append(0x5C)
                    case UInt8(ascii: "/"): bytes.append(0x2F)
                    case UInt8(ascii: "b"): bytes.append(0x08)
                    case UInt8(ascii: "f"): bytes.append(0x0C)
                    case UInt8(ascii: "n"): bytes.append(0x0A)
                    case UInt8(ascii: "r"): bytes.append(0x0D)
                    case UInt8(ascii: "t"): bytes.append(0x09)
                    case UInt8(ascii: "u"):
                        var cp = try hex4()
                        if (0xD800...0xDBFF).contains(cp), i + 6 <= b.count, b[i] == UInt8(ascii: "\\"), b[i + 1] == UInt8(ascii: "u") {
                            i += 2
                            let lo = try hex4()
                            if (0xDC00...0xDFFF).contains(lo) { cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00) }
                            else { cp = 0xFFFD }
                        }
                        let scalar = Unicode.Scalar(cp) ?? "\u{FFFD}"
                        bytes.append(contentsOf: Array(String(Character(scalar)).utf8))
                    default: throw JSONError.invalid("bad escape", offset: i)
                    }
                } else {
                    bytes.append(c); i += 1
                }
            }
            return String(decoding: bytes, as: UTF8.self)
        }
        mutating func number() throws -> Double {
            let start = i
            while i < b.count, let c = Optional(b[i]), (c >= 0x30 && c <= 0x39) || c == UInt8(ascii: "-") || c == UInt8(ascii: "+") || c == UInt8(ascii: ".") || c == UInt8(ascii: "e") || c == UInt8(ascii: "E") { i += 1 }
            guard i > start, let d = Double(String(decoding: b[start..<i], as: UTF8.self)) else { throw JSONError.invalid("bad number", offset: start) }
            return d
        }
    }
}
