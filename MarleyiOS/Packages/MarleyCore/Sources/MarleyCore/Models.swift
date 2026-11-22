import Foundation

/// One transaction. A typed view over the original JSON object: fields the app doesn't know about
/// (now or in the future) are kept as they are, and untouched transactions serialize back byte-for-byte.
public struct Txn: Identifiable, Equatable, Sendable {
    public var raw: JSONObject

    public init(raw: JSONObject) { self.raw = raw }

    /// A new transaction with the same field set the web app writes.
    public init(id: Int, date: String, desc: String, acct: String, out: Double, in_: Double,
                notes: String = "", cat: String = "", style: String = "normal",
                recurring: Bool = false, warning: Bool = false, cleared: Bool = false, locked: Bool = false) {
        raw = JSONObject([
            ("id", .number(Double(id))), ("date", .string(date)), ("desc", .string(desc)), ("acct", .string(acct)),
            ("notes", .string(notes)), ("cat", .string(cat)), ("style", .string(style)),
            ("out", .number(out)), ("in_", .number(in_)),
            ("recurring", .bool(recurring)), ("warning", .bool(warning)),
            ("cleared", .bool(cleared)), ("locked", .bool(locked)),
        ])
    }

    public var id: Int { get { raw["id"]?.intValue ?? 0 } set { raw["id"] = .number(Double(newValue)) } }
    public var date: String { get { raw["date"]?.stringValue ?? "" } set { raw["date"] = .string(newValue) } }
    public var desc: String { get { raw["desc"]?.stringValue ?? "" } set { raw["desc"] = .string(newValue) } }
    public var acct: String { get { raw["acct"]?.stringValue ?? "—" } set { raw["acct"] = .string(newValue) } }
    public var out: Double { get { raw["out"]?.doubleValue ?? 0 } set { raw["out"] = .number(newValue) } }
    public var in_: Double { get { raw["in_"]?.doubleValue ?? 0 } set { raw["in_"] = .number(newValue) } }
    public var notes: String { get { raw["notes"]?.stringValue ?? "" } set { raw["notes"] = .string(newValue) } }
    public var cat: String { get { raw["cat"]?.stringValue ?? "" } set { raw["cat"] = .string(newValue) } }
    public var style: String { get { raw["style"]?.stringValue ?? "normal" } set { raw["style"] = .string(newValue) } }
    public var recurring: Bool { get { raw["recurring"]?.boolValue ?? false } set { raw["recurring"] = .bool(newValue) } }
    public var warning: Bool { get { raw["warning"]?.boolValue ?? false } set { raw["warning"] = .bool(newValue) } }
    public var cleared: Bool { get { raw["cleared"]?.boolValue ?? false } set { raw["cleared"] = .bool(newValue) } }
    public var locked: Bool { get { raw["locked"]?.boolValue ?? false } set { raw["locked"] = .bool(newValue) } }

    public var month: String { String(date.prefix(7)) }
    public var net: Double { in_ - out }
    public var isIncome: Bool { in_ > 0 }
    public var amount: Double { out > 0 ? out : in_ }
    /// Same rule the web app uses for "copies itself into next month".
    public var isRecurringKind: Bool { (recurring || ["fixed", "salary", "critical"].contains(style)) && style != "opening" }
    public var isUncertain: Bool { warning || style == "warning" }
}

/// The whole document stored in the Gist (`marley-data.json`).
public struct AppData: Equatable, Sendable {
    /// Everything except `txns`, in original key order (the txns slot keeps its position).
    public var rest: JSONObject
    public var txns: [Txn]

    public init(rest: JSONObject, txns: [Txn]) { self.rest = rest; self.txns = txns }

    public static func parse(_ text: String) throws -> AppData {
        guard case .object(let o) = try JSON.parse(text) else { throw JSONError.invalid("top level is not an object", offset: 0) }
        return try AppData(object: o)
    }
    public init(object o: JSONObject) throws {
        guard let arr = o["txns"]?.arrayValue else { throw JSONError.invalid("missing txns array", offset: 0) }
        var txns: [Txn] = []
        txns.reserveCapacity(arr.count)
        for v in arr { guard case .object(let t) = v else { throw JSONError.invalid("txn is not an object", offset: 0) }; txns.append(Txn(raw: t)) }
        var rest = o
        rest["txns"] = .array([])  // placeholder keeps the key position
        self.rest = rest
        self.txns = txns
    }

    public var object: JSONObject {
        var o = rest
        o["txns"] = .array(txns.map { .object($0.raw) })
        return o
    }
    public func serialized() -> String { JSON.serialize(.object(object)) }

    // MARK: Typed accessors

    public var lastModified: Double {
        get { rest["_lastModified"]?.doubleValue ?? 0 }
        set { rest["_lastModified"] = .number(newValue) }
    }
    public var months: [String] {
        get { (rest["months"]?.arrayValue ?? []).compactMap(\.stringValue) }
        set { rest["months"] = .array(newValue.map { .string($0) }) }
    }
    /// Opening balances (app start, 23/02/2026).
    public var openingBalance: [String: Double] {
        let b = rest["balances"]?.objectValue
        return ["Revolut": b?["rev"]?.doubleValue ?? 0, "Wise": b?["wise"]?.doubleValue ?? 0, "Swile": b?["swile"]?.doubleValue ?? 0]
    }
    public var budgetMonths: [String] { rest["budgets"]?.objectValue?.keys ?? [] }
    public func budgets(for month: String) -> [String: Double] {
        var out: [String: Double] = [:]
        for (k, v) in rest["budgets"]?.objectValue?[month]?.objectValue?.pairs ?? [] { out[k] = v.doubleValue ?? 0 }
        return out
    }
    public func hasBudget(for month: String) -> Bool { rest["budgets"]?.objectValue?[month] != nil }
    public func budget(_ month: String, _ cat: String) -> Double { rest["budgets"]?.objectValue?[month]?.objectValue?[cat]?.doubleValue ?? 0 }
    public mutating func setBudget(_ month: String, _ cat: String, _ value: Double) {
        var all = rest["budgets"]?.objectValue ?? JSONObject()
        var m = all[month]?.objectValue ?? JSONObject()
        m[cat] = .number(value)
        all[month] = .object(m)
        rest["budgets"] = .object(all)
    }
    public mutating func ensureBudgetMonth(_ month: String) {
        var all = rest["budgets"]?.objectValue ?? JSONObject()
        if all[month] == nil { all[month] = .object(JSONObject()); rest["budgets"] = .object(all) }
    }
    public func skipRecurring(_ month: String) -> [String] {
        (rest["skipRecurring"]?.objectValue?[month]?.arrayValue ?? []).compactMap(\.stringValue)
    }
    public mutating func addSkipRecurring(_ month: String, _ desc: String) {
        var all = rest["skipRecurring"]?.objectValue ?? JSONObject()
        var list = all[month]?.arrayValue ?? []
        if !list.contains(.string(desc)) { list.append(.string(desc)) }
        all[month] = .array(list)
        rest["skipRecurring"] = .object(all)
    }
    public var goals: JSONValue? { rest["goals"] }

    public var nextId: Int { max(txns.map(\.id).max() ?? 0, 24) + 1 }
    public func txn(_ id: Int) -> Txn? { txns.first { $0.id == id } }
    public mutating func update(_ id: Int, _ change: (inout Txn) -> Void) {
        if let i = txns.firstIndex(where: { $0.id == id }) { change(&txns[i]) }
    }
    public var lockedCount: Int { txns.reduce(0) { $0 + ($1.locked ? 1 : 0) } }
}

public enum Accounts {
    public static let all = ["Revolut", "Wise", "Swile"]
    public static func icon(_ a: String) -> String { a == "Swile" ? "🍽" : "💳" }
}
