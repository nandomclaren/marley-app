import Foundation

public enum Installments {
    public static let max = 60
    public struct Part: Equatable, Sendable { public let i: Int; public let date: String; public let amount: Double }

    /// installmentPlan(): monthly parts from the purchase date; the 1st gets the leftover cents.
    public static func plan(total: Double, count n: Int, date: String) -> [Part] {
        let cents = Int((total * 100).rounded())
        let base = cents / n
        let first = cents - base * (n - 1)
        return (0..<n).map { k in Part(i: k + 1, date: Day.addMonths(date, k), amount: Double(k == 0 ? first : base) / 100) }
    }

    public struct Parsed: Equatable, Sendable { public let base: String; public let i: Int; public let n: Int }
    /// "Sofá 2/6" → (Sofá, 2, 6)
    public static func parse(_ desc: String) -> Parsed? {
        let pattern = #"^(.*\S)\s+(\d{1,2})/(\d{1,2})$"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: desc, range: NSRange(desc.startIndex..., in: desc)),
              let r1 = Range(m.range(at: 1), in: desc), let r2 = Range(m.range(at: 2), in: desc), let r3 = Range(m.range(at: 3), in: desc),
              let i = Int(desc[r2]), let n = Int(desc[r3]), n >= 2, i >= 1, i <= n else { return nil }
        return Parsed(base: String(desc[r1]), i: i, n: n)
    }

    /// followingInstallments(): later parts of the same purchase (same base, count, account, expected month).
    public static func following(_ d: AppData, _ txn: Txn) -> [Txn] {
        guard let p = parse(txn.desc) else { return [] }
        return d.txns.filter { t in
            guard t.id != txn.id, t.acct == txn.acct, let q = parse(t.desc), q.base == p.base, q.n == p.n, q.i > p.i else { return false }
            return t.month == String(Day.addMonths(txn.date, q.i - p.i).prefix(7))
        }
    }

    /// submitTxn() parcelado branch.
    @discardableResult
    public static func add(_ d: inout AppData, total: Double, count: Int, date: String, desc: String, acct: String,
                           isIncome: Bool, cat: String, notes: String, uncertain: Bool) -> [Int] {
        plan(total: total, count: count, date: date).map { p in
            let t = Txn(id: d.nextId, date: p.date, desc: "\(desc) \(p.i)/\(count)", acct: acct,
                        out: isIncome ? 0 : p.amount, in_: isIncome ? p.amount : 0, notes: notes, cat: cat,
                        recurring: false, warning: uncertain)
            d.txns.append(t)
            return t.id
        }
    }
}
