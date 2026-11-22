import Foundation

/// Calculations, each one a port of the web app function named in its comment.
public enum Ledger {
    /// The app started on 23/02/2026; February is excluded from budgets and analyses.
    public static let startMonth = "2026-02"

    // MARK: Balances

    /// Balance of each account on a date: opening balance + every transaction up to that date.
    public static func balances(_ d: AppData, asOf date: String) -> [String: Double] {
        var b = d.openingBalance
        for t in d.txns where t.date <= date && t.style != "opening" && b[t.acct] != nil { b[t.acct]! += t.net }
        return b
    }

    public struct RunningRow: Identifiable, Sendable { public let txn: Txn; public let total: Double; public var id: Int { txn.id } }
    /// compute(): every transaction sorted by date then id, with the running total of all accounts.
    public static func running(_ d: AppData) -> [RunningRow] {
        var b = d.openingBalance
        var total = b.values.reduce(0, +)
        return sorted(d.txns).map { t in
            if b[t.acct] != nil { b[t.acct]! += t.net; total += t.net }
            return RunningRow(txn: t, total: total)
        }
    }
    public static func sorted(_ txns: [Txn]) -> [Txn] { txns.sorted { $0.date != $1.date ? $0.date < $1.date : $0.id < $1.id } }

    public struct AccountSummary: Sendable { public let working: Double; public let cleared: Double; public let uncleared: Double }
    /// renderContas() header cards: global, transactions up to today only.
    public static func accountSummary(_ d: AppData, _ acct: String, today: String) -> AccountSummary {
        let start = d.openingBalance[acct] ?? 0
        var cleared = start, uncleared = 0.0
        for t in d.txns where t.acct == acct && t.style != "opening" && t.date <= today {
            if t.cleared || t.locked { cleared += t.net } else { uncleared += t.net }
        }
        return AccountSummary(working: cleared + uncleared, cleared: cleared, uncleared: uncleared)
    }
    /// renderContas() rows: an account's transactions in a month with the account's running balance.
    public static func accountRows(_ d: AppData, _ acct: String, month: String) -> [RunningRow] {
        let all = sorted(d.txns.filter { $0.acct == acct && $0.style != "opening" })
        var bal = (d.openingBalance[acct] ?? 0) + all.filter { $0.date < month + "-01" }.reduce(0) { $0 + $1.net }
        return all.filter { $0.month == month }.map { t in bal += t.net; return RunningRow(txn: t, total: bal) }
    }

    public struct MonthOverview: Equatable, Sendable {
        public let start: Double          // "Início de nov": saldo total antes do 1º dia do mês
        public let today: Double          // "Saldo hoje": saldo total até hoje (independe do mês escolhido)
        public let projectedEnd: Double   // "Projetado fim do mês": saldo após a última transação do mês
        public let minimum: Double?       // "Mínimo do mês": menor saldo corrido dentro do mês
        public let minimumDate: String?
        /// Abaixo disso o web pinta o mínimo de vermelho.
        public static let lowThreshold = 800.0
    }
    /// Os 4 cards do topo do Fluxo no web (render() → s-part, s-hoje, s-final, s-min).
    public static func monthOverview(_ d: AppData, month: String, today: String) -> MonthOverview {
        let rows = running(d)
        let opening = d.openingBalance.values.reduce(0, +)
        let monthStart = month + "-01", monthEnd = String(format: "%@-%02d", month, Day.lastDay(month))
        let start = rows.last(where: { $0.txn.date < monthStart && $0.txn.style != "opening" })?.total ?? opening
        let inMonth = rows.filter { $0.txn.date >= monthStart && $0.txn.date <= monthEnd }
        let end = inMonth.last?.total ?? start
        let now = rows.last(where: { $0.txn.date <= today })?.total ?? start
        let minRow = inMonth.min { $0.total < $1.total }  // primeira ocorrência do menor valor, como no web
        return MonthOverview(start: start, today: now, projectedEnd: end, minimum: minRow?.total, minimumDate: minRow?.txn.date)
    }

    // MARK: Budget

    /// Spent per category in a month (out − in).
    public static func spent(_ d: AppData, month: String) -> [String: Double] {
        var s: [String: Double] = [:]
        for t in d.txns where !t.cat.isEmpty && t.month == month { s[t.cat, default: 0] += t.out - t.in_ }
        return s
    }
    /// budgetCarry(): carried balance per category at the start of month m.
    public static func budgetCarry(_ d: AppData, month m: String) -> [String: Double] {
        var chain: [String] = []
        var cur = m
        for _ in 0..<24 {
            let prev = Day.prevMonth(cur)
            if prev <= startMonth { break }
            if !d.hasBudget(for: prev) { break }
            chain.insert(prev, at: 0)
            cur = prev
        }
        var acc: [String: Double] = [:]
        for mo in chain {
            let b = d.budgets(for: mo), s = spent(d, month: mo)
            var next: [String: Double] = [:]
            for cat in Categories.all { next[cat] = (acc[cat] ?? 0) + (b[cat] ?? 0) - (s[cat] ?? 0) }
            acc = next
        }
        return acc
    }
    public struct CategoryLine: Identifiable, Sendable {
        public let cat: String; public let carry: Double; public let budgeted: Double; public let spent: Double
        public var available: Double { carry + budgeted - spent }
        public var id: String { cat }
    }
    public static func categoryLines(_ d: AppData, month: String) -> [CategoryLine] {
        let carry = budgetCarry(d, month: month), b = d.budgets(for: month), s = spent(d, month: month)
        return Categories.all.map { CategoryLine(cat: $0, carry: carry[$0] ?? 0, budgeted: b[$0] ?? 0, spent: s[$0] ?? 0) }
    }
    /// computeAAlocar(): received (post-Feb, up to today) uncategorized money minus everything ever budgeted.
    public static func aAlocar(_ d: AppData, today: String) -> Double {
        let uncategorized = d.txns.filter { $0.date > "2026-02-28" && $0.cat.isEmpty && $0.style != "opening" && $0.date <= today }.reduce(0) { $0 + $1.net }
        let allocations = d.budgetMonths.filter { $0 > startMonth }.reduce(0.0) { acc, m in acc + d.budgets(for: m).values.reduce(0, +) }
        return uncategorized - allocations
    }
    /// submitMove(): move budget between categories within a month.
    public static func moveMoney(_ d: inout AppData, month: String, from: String, to: String, amount: Double) {
        d.setBudget(month, from, d.budget(month, from) - amount)
        d.setBudget(month, to, d.budget(month, to) + amount)
    }

    // MARK: Months and recurring transactions

    public static let monthsAhead = 2
    public static func monthsAheadTarget(today: String) -> String {
        var m = String(today.prefix(7))
        for _ in 0..<monthsAhead { m = Day.nextMonth(m) }
        return m
    }
    /// ensureMonthsAhead(): adds the missing months up to current + 2 (filling gaps), empty budgets, and their
    /// recurring transactions in order. Only adds. Returns the months added.
    @discardableResult
    public static func ensureMonthsAhead(_ d: inout AppData, today: String) -> [String] {
        var months = d.months
        guard var last = months.sorted().last else { return [] }
        let target = monthsAheadTarget(today: today)
        var added: [String] = []
        while last < target {
            last = Day.nextMonth(last)
            if !months.contains(last) { months.append(last); added.append(last) }
            d.ensureBudgetMonth(last)
        }
        guard !added.isEmpty else { return [] }
        d.months = months.sorted()
        for m in added { generateRecurring(&d, month: m) }
        return added
    }
    /// autoGenerateRecurring(): copies last month's recurring transactions into month m.
    @discardableResult
    public static func generateRecurring(_ d: inout AppData, month m: String) -> Int {
        let prev = Day.prevMonth(m)
        let source = d.txns.filter { $0.date.hasPrefix(prev) && $0.isRecurringKind }
        let skip = Set(d.skipRecurring(m))
        let months = Set(d.months)
        var added = 0
        for t in source {
            if d.txns.contains(where: { $0.date.hasPrefix(m) && $0.desc == t.desc }) { continue }
            if skip.contains(t.desc) { continue }
            let next = Day.addMonths(t.date, 1)
            guard months.contains(String(next.prefix(7))) else { continue }
            var copy = t
            copy.id = d.nextId
            copy.date = next
            copy.cleared = false
            copy.locked = false
            d.txns.append(copy)
            added += 1
        }
        return added
    }
    /// resetFutureLocks(): nothing in the future can be reconciled.
    public static func resetFutureLocks(_ d: inout AppData, today: String) {
        for i in d.txns.indices where d.txns[i].date > today && d.txns[i].locked { d.txns[i].locked = false }
    }

    // MARK: Editing

    /// delTxnFromModal(): deleting a recurring transaction remembers not to regenerate it for that month.
    public static func delete(_ d: inout AppData, ids: Set<Int>) {
        for t in d.txns where ids.contains(t.id) && t.isRecurringKind { d.addSkipRecurring(t.month, t.desc) }
        d.txns.removeAll { ids.contains($0.id) }
    }

    // MARK: Reconciliation (Contas)

    public static func clearedBalance(_ d: AppData, _ acct: String, today: String) -> Double { accountSummary(d, acct, today: today).cleared }
    /// lockClearedTxns(): cleared → locked for the account.
    public static func lockCleared(_ d: inout AppData, _ acct: String) {
        for i in d.txns.indices where d.txns[i].acct == acct && d.txns[i].cleared && !d.txns[i].locked {
            d.txns[i].locked = true
            d.txns[i].cleared = false
        }
    }
    /// recSubmitCorrection(): lock cleared, then add an already-locked correction for the difference.
    public static func reconcileWithCorrection(_ d: inout AppData, _ acct: String, bankBalance: Double, today: String) -> Txn? {
        let found = clearedBalance(d, acct, today: today)
        let diff = ((bankBalance - found) * 100).rounded() / 100
        lockCleared(&d, acct)
        guard diff != 0 else { return nil }
        let t = Txn(id: d.nextId, date: today, desc: "🔧 Transação de correção", acct: acct,
                    out: diff < 0 ? -diff : 0, in_: diff > 0 ? diff : 0,
                    notes: "Correção de reconciliação (esperado \(Money.eur(bankBalance)), encontrado \(Money.eur(found)))",
                    locked: true)
        d.txns.append(t)
        return t
    }

    // MARK: Age of money

    /// calcAgeOfMoney(): FIFO, oldest income consumed first. nil when spending exceeded income.
    public static func ageOfMoney(_ d: AppData, asOf: String) -> Int? {
        let ob = d.openingBalance
        let initBal = (ob["Revolut"] ?? 0) + (ob["Wise"] ?? 0) + (ob["Swile"] ?? 0)
        var incomes: [(date: String, amount: Double)] = []
        if initBal > 0 { incomes.append((sorted(d.txns).first?.date ?? asOf, initBal)) }
        incomes += sorted(d.txns.filter { $0.in_ > 0 && $0.style != "opening" && $0.date <= asOf }).map { ($0.date, $0.in_) }
        let spendings = sorted(d.txns.filter { $0.out > 0 && $0.style != "opening" && $0.date <= asOf })
        guard !incomes.isEmpty, !spendings.isEmpty else { return nil }
        var idx = 0, remaining = incomes[0].amount
        outer: for s in spendings {
            var left = s.out
            while left > 0.005 {
                if idx >= incomes.count { break outer }
                let chunk = min(remaining, left)
                left -= chunk; remaining -= chunk
                if remaining < 0.005 { idx += 1; if idx < incomes.count { remaining = incomes[idx].amount } }
            }
        }
        guard idx < incomes.count else { return nil }
        return Day.daysBetween(incomes[idx].date, asOf)
    }
}

public enum Money {
    /// "1 234,56 €" like toLocaleString('fr-FR', {style:'currency', currency:'EUR'}).
    public static func eur(_ n: Double, signed: Bool = false) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        let s = f.string(from: NSNumber(value: abs(n))) ?? String(format: "%.2f €", abs(n))
        if n < -0.004 { return "−" + s }
        return signed && n > 0.004 ? "+" + s : s
    }
    public static func round2(_ n: Double) -> Double { (n * 100).rounded() / 100 }
}
