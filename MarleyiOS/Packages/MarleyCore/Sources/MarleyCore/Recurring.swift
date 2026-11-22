import Foundation

/// Editar/apagar uma transação recorrente: só esta, esta e as futuras, ou todas.
/// Reconciliadas (🔒) nunca são alteradas nem apagadas em massa: são histórico confirmado.
public enum RecurringScope: Sendable { case this, thisAndFuture, all }

public struct TxnEdit: Sendable {
    public var date: String, desc: String, acct: String, amount: Double, isIncome: Bool
    public var cat: String, notes: String, recurring: Bool, uncertain: Bool
    public init(date: String, desc: String, acct: String, amount: Double, isIncome: Bool, cat: String, notes: String, recurring: Bool, uncertain: Bool) {
        self.date = date; self.desc = desc; self.acct = acct; self.amount = amount; self.isIncome = isIncome
        self.cat = cat; self.notes = notes; self.recurring = recurring; self.uncertain = uncertain
    }
}

public enum Recurring {
    /// Todas as instâncias da série de `t` (mesma descrição e conta, recorrentes), incluindo `t`.
    public static func series(_ d: AppData, _ t: Txn) -> [Txn] {
        guard t.isRecurringKind else { return [] }
        return Ledger.sorted(d.txns.filter { $0.isRecurringKind && $0.desc == t.desc && $0.acct == t.acct })
    }
    /// As outras instâncias (não reconciliadas) que um escopo alcançaria.
    public static func others(_ d: AppData, _ t: Txn, _ scope: RecurringScope) -> [Txn] {
        series(d, t).filter { o in
            o.id != t.id && !o.locked && (scope == .all || (scope == .thisAndFuture && o.date > t.date))
        }
    }
    /// Vale perguntar o escopo? Só se a série tem outras instâncias alteráveis.
    public static func hasOthers(_ d: AppData, _ t: Txn) -> Bool { !others(d, t, .all).isEmpty }

    /// Aplica a edição a `original` e, conforme o escopo, só os campos alterados às outras instâncias.
    public static func applyEdit(_ d: inout AppData, original: Txn, edit e: TxnEdit, scope: RecurringScope) {
        let targets = scope == .this ? [] : others(d, original, scope)
        d.update(original.id) { t in set(&t, e) }
        let changedDay = Day.parts(e.date).d != Day.parts(original.date).d
        for o in targets {
            d.update(o.id) { t in
                if e.desc != original.desc { t.desc = e.desc }
                if e.acct != original.acct { t.acct = e.acct }
                if e.cat != original.cat { t.cat = e.cat }
                if e.notes != original.notes { t.notes = e.notes }
                if e.uncertain != original.isUncertain { t.warning = e.uncertain }
                if e.isIncome != original.isIncome || abs(e.amount - original.amount) > 0.004 {
                    t.out = e.isIncome ? 0 : e.amount; t.in_ = e.isIncome ? e.amount : 0
                }
                let wasRecurring = original.recurring || original.style == "fixed"
                if e.recurring != wasRecurring {
                    t.recurring = e.recurring
                    if !e.recurring && t.style == "fixed" { t.style = "normal" }
                }
                if changedDay { t.date = String(format: "%@-%02d", t.month, min(Day.parts(e.date).d, Day.lastDay(t.month))) }
            }
        }
    }
    /// Mesmos campos que a edição normal (updateTransaction) grava.
    static func set(_ t: inout Txn, _ e: TxnEdit) {
        t.date = e.date; t.desc = e.desc; t.acct = e.acct; t.cat = e.cat; t.notes = e.notes
        t.out = e.isIncome ? 0 : e.amount; t.in_ = e.isIncome ? e.amount : 0
        if !["opening", "salary", "critical"].contains(t.style) { t.style = "normal" }
        t.recurring = e.recurring; t.warning = e.uncertain
    }

    /// Apaga conforme o escopo. "Esta e as futuras"/"todas" impedem a série de ser recriada nos meses seguintes.
    public static func delete(_ d: inout AppData, _ t: Txn, scope: RecurringScope) {
        var ids: Set<Int> = [t.id]
        if scope != .this { ids.formUnion(others(d, t, scope).map(\.id)) }
        if scope == .all {
            // reconciliadas ficam, mas deixam de ser recorrentes (senão a série recomeçaria a partir delas)
            let kept = series(d, t).filter { $0.locked && $0.id != t.id }
            for keep in kept {
                d.update(keep.id) { x in x.recurring = false; if x.style == "fixed" { x.style = "normal" } }
            }
            // salário/crítica são recorrentes pelo estilo: impede a cópia para o mês seguinte à última que ficou
            if let last = kept.last { d.addSkipRecurring(Day.nextMonth(last.month), last.desc) }
        }
        Ledger.delete(&d, ids: ids) // anota skipRecurring para cada mês apagado
    }
}
