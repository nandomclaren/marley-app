import Foundation

/// The advisor's data side: same context, search, validation and apply rules as the web app (index.html "IA").
public enum AI {
    public static let model = "claude-sonnet-5-5"
    public static let apiVersion = "2026-10-21"
    /// US$ per million tokens (Sonnet 5.5): input, output, 5-min cache write, cache read.
    static let price = (input: 2.0, output: 10.0, cacheWrite: 2.5, cacheRead: 0.10)

    // MARK: Context

    static func money(_ n: Double) -> String {
        let r = (n * 100).rounded() / 100
        return (r < 0 ? "-" : "") + String(format: "%.2f", abs(r))
    }
    static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "|", with: " ").trimmingCharacters(in: .whitespaces)
    }
    public static func line(_ t: Txn) -> String {
        let val = t.in_ > 0 ? "+" + money(t.in_) : "-" + money(t.out)
        var flags = ""
        if t.locked { flags += "L" }
        if t.cleared && !t.locked { flags += "C" }
        if t.recurring || ["fixed", "salary", "critical"].contains(t.style) { flags += "R" }
        if t.isUncertain { flags += "W" }
        return "\(t.id)|\(t.date)|\(clean(t.desc))|\(t.acct)|\(val)|\(clean(t.cat))|\(flags)|\(clean(t.notes))"
    }
    static let header = "id|data|descrição|conta|valor|categoria|marcas|notas"
    static let weekdays = ["domingo", "segunda", "terça", "quarta", "quinta", "sexta", "sábado"]
    static func todayLabel(_ today: String) -> String {
        guard let date = Day.date(today) else { return today }
        let wd = Calendar(identifier: .gregorian).component(.weekday, from: date) - 1
        return "\(today) (\(weekdays[wd]))"
    }
    static func balancesLine(_ d: AppData, _ today: String) -> String {
        let b = Ledger.balances(d, asOf: today)
        return "Revolut \(money(b["Revolut"]!)) · Wise \(money(b["Wise"]!)) · Swile \(money(b["Swile"]!))"
    }

    /// aiBuildContext(): balances, current budget, monthly summary of all history, transactions from this month on.
    public static func context(_ d: AppData, today: String) -> String {
        let cm = String(today.prefix(7))
        let b = Ledger.balances(d, asOf: today), ob = d.openingBalance
        var L: [String] = []
        L.append("Hoje: \(todayLabel(today)). Mês atual: \(cm). Meses no app: \(d.months.joined(separator: ", ")).")
        L.append("")
        L.append("Saldos das contas hoje: \(balancesLine(d, today)) · Total \(money(b.values.reduce(0, +)))")
        L.append("Saldos iniciais do app (23/02/2026): Revolut \(money(ob["Revolut"]!)) · Wise \(money(ob["Wise"]!)) · Swile \(money(ob["Swile"]!))")
        L.append("A Alocar hoje: \(money(Ledger.aAlocar(d, today: today)))")
        L.append("")
        L.append("Categorias por grupo:")
        for g in Categories.groups { L.append("- \(g.group): \(g.cats.joined(separator: " ; "))") }
        L.append("")
        L.append("Orçamento de \(cm) por categoria: carregado dos meses anteriores | orçado | gasto | disponível")
        for l in Ledger.categoryLines(d, month: cm) where l.carry != 0 || l.budgeted != 0 || l.spent != 0 {
            L.append("\(l.cat) | \(money(l.carry)) | \(money(l.budgeted)) | \(money(l.spent)) | \(money(l.available))")
        }
        L.append("")
        L.append("Orçado por mês (só valores diferentes de zero):")
        for m in d.budgetMonths.sorted() {
            let o = d.rest["budgets"]?.objectValue?[m]?.objectValue?.pairs ?? []
            let parts = o.compactMap { (c, v) -> String? in let n = v.doubleValue ?? 0; return n != 0 ? "\(c)=\(money(n))" : nil }
            if !parts.isEmpty { L.append("\(m): \(parts.joined(separator: " ; "))") }
        }
        if let goals = d.goals, case .object(let g) = goals, g.count > 0 {
            L.append("")
            L.append("Metas por categoria (JSON): " + JSON.serialize(goals))
        }
        L.append("")
        L.append("Resumo mensal de todo o histórico (inclui previsões nos meses futuros; gasto por categoria = saídas − entradas):")
        struct M { var n = 0, inn = 0.0, out = 0.0, uncIn = 0.0, uncOut = 0.0, cats: [String: Double] = [:], order: [String] = [] }
        var byMonth: [String: M] = [:]
        for t in d.txns where t.style != "opening" {
            var r = byMonth[t.month] ?? M()
            r.n += 1; r.inn += t.in_; r.out += t.out
            if t.cat.isEmpty { r.uncIn += t.in_; r.uncOut += t.out }
            else { if r.cats[t.cat] == nil { r.order.append(t.cat) }; r.cats[t.cat, default: 0] += t.out - t.in_ }
            byMonth[t.month] = r
        }
        for m in byMonth.keys.sorted() {
            let r = byMonth[m]!
            // stable sort by value desc (JS Array.sort is stable; ties keep first-seen order)
            let cats = r.order.enumerated().filter { abs(r.cats[$0.element]!) > 0.005 }
                .sorted { let a = r.cats[$0.element]!, b = r.cats[$1.element]!; return a != b ? a > b : $0.offset < $1.offset }
                .map { "\($0.element)=\(money(r.cats[$0.element]!))" }.joined(separator: " ; ")
            L.append("\(m): \(r.n) transações · entradas \(money(r.inn)) · saídas \(money(r.out)) · sem categoria: entradas \(money(r.uncIn)), saídas \(money(r.uncOut))\(cats.isEmpty ? "" : " · por categoria: " + cats)")
        }
        L.append("")
        let recent = Ledger.sorted(d.txns.filter { $0.date >= cm + "-01" })
        L.append("Transações de \(cm) em diante (\(recent.count) de \(d.txns.count) no total; as anteriores estão disponíveis via search_transactions), em ordem de data:")
        L.append(header)
        for t in recent { L.append(line(t)) }
        return L.joined(separator: "\n")
    }

    // MARK: Search (read-only tool)

    static func norm(_ s: String) -> String { s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR")) }

    public static func search(_ d: AppData, _ q: JSONObject) -> (result: String, count: Int) {
        let str = { (k: String) -> String? in q[k]?.stringValue }
        if let c = str("category"), !c.isEmpty, !Categories.all.contains(c) {
            return ("A categoria \"\(c)\" não existe. Use um nome exato da lista de categorias, ou \"\" para sem categoria.", 0)
        }
        let text = str("text").flatMap { $0.isEmpty ? nil : norm($0) }
        let rows = Ledger.sorted(d.txns.filter { t in
            if let f = str("date_from"), !f.isEmpty, t.date < f { return false }
            if let to = str("date_to"), !to.isEmpty, t.date > to { return false }
            if let c = str("category"), t.cat != c { return false }
            if let a = str("account"), !a.isEmpty, t.acct != a { return false }
            if let ty = str("type"), !ty.isEmpty, ty == "entrada" ? !(t.in_ > 0) : !(t.out > 0) { return false }
            if let text, !norm("\(t.desc) \(t.notes)").contains(text) { return false }
            return true
        })
        let limit = min(max(q["limit"]?.intValue ?? 200, 1), 500)
        let shown = rows.count > limit ? Array(rows.suffix(limit)) : rows
        let inSum = rows.reduce(0) { $0 + $1.in_ }, outSum = rows.reduce(0) { $0 + $1.out }
        let head = "\(rows.count) transações encontradas\(rows.count > limit ? " (mostrando as \(limit) mais recentes)" : ""). Soma: entradas \(money(inSum)), saídas \(money(outSum))."
        return (rows.isEmpty ? head : head + "\n" + header + "\n" + shown.map(line).joined(separator: "\n"), rows.count)
    }
    public static func searchLabel(_ q: JSONObject, count: Int?) -> String {
        func sd(_ s: String) -> String { "\(Day.short(s))/\(s.dropFirst(2).prefix(2))" }
        var parts: [String] = []
        let f = q["date_from"]?.stringValue, t = q["date_to"]?.stringValue
        if let f, let t { parts.append("\(sd(f)) a \(sd(t))") } else if let f { parts.append("desde \(sd(f))") } else if let t { parts.append("até \(sd(t))") }
        if let x = q["text"]?.stringValue, !x.isEmpty { parts.append("\"\(x)\"") }
        if let c = q["category"]?.stringValue { parts.append(c.isEmpty ? "sem categoria" : c) }
        if let a = q["account"]?.stringValue { parts.append(a) }
        if let ty = q["type"]?.stringValue { parts.append(ty == "entrada" ? "entradas" : "saídas") }
        return "🔎 Consultou \(parts.isEmpty ? "todas as transações" : parts.joined(separator: " · "))\(count.map { " (\($0))" } ?? "")"
    }

    // MARK: Proposals

    public struct Operation: Sendable {
        public let raw: JSONObject
        public var op: String { raw["op"]?.stringValue ?? "" }
        public var id: Int? { raw["id"]?.intValue }
        public var date: String? { raw["date"]?.stringValue }
        public var desc: String? { raw["desc"]?.stringValue }
        public var acct: String? { raw["acct"]?.stringValue }
        public var type: String? { raw["type"]?.stringValue }
        public var amount: Double? { raw["amount"]?.doubleValue }
        public var cat: String? { raw["cat"]?.stringValue }
        public var notes: String? { raw["notes"]?.stringValue }
        public var aConfirmar: Bool? { raw["a_confirmar"]?.boolValue }
        public var recurring: Bool? { raw["recurring"]?.boolValue }
        public var month: String? { raw["month"]?.stringValue }
        public var reason: String { raw["reason"]?.stringValue ?? "" }
    }
    public static func operations(_ input: JSONObject) -> [Operation] {
        (input["operations"]?.arrayValue ?? []).compactMap { $0.objectValue.map(Operation.init) }
    }

    static func isDate(_ s: String?) -> Bool {
        guard let s, s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        let p = Day.parts(s); return (1...12).contains(p.m) && p.d >= 1 && p.d <= Day.lastDay(Day.month(p.y, p.m))
    }
    static func isCat(_ c: String) -> Bool { c.isEmpty || Categories.all.contains(c) }

    /// aiValidate(): semantic checks beyond the strict schema.
    public static func validate(_ d: AppData, _ input: JSONObject) -> [String] {
        let ops = operations(input)
        if ops.isEmpty { return ["operations está vazio"] }
        var errs: [String] = []
        for (k, op) in ops.enumerated() {
            let p = "operação \(k + 1) (\(op.op))"
            switch op.op {
            case "add":
                if !isDate(op.date) { errs.append("\(p): date inválida") }
                if (op.desc ?? "").trimmingCharacters(in: .whitespaces).isEmpty { errs.append("\(p): desc vazia") }
                if !Accounts.all.contains(op.acct ?? "") { errs.append("\(p): acct deve ser Revolut, Wise ou Swile") }
                if !["saida", "entrada"].contains(op.type ?? "") { errs.append("\(p): type deve ser saida ou entrada") }
                if !((op.amount ?? 0) > 0) { errs.append("\(p): amount deve ser positivo") }
                if let c = op.cat, !isCat(c) { errs.append("\(p): categoria \"\(c)\" não existe") }
            case "update", "delete":
                guard let id = op.id, let t = d.txn(id) else { errs.append("\(p): transação \(op.id.map(String.init) ?? "?") não existe"); continue }
                if t.locked { errs.append("\(p): transação \(id) está reconciliada (L) e não pode ser alterada") }
                if op.op == "update" {
                    if op.date != nil && !isDate(op.date) { errs.append("\(p): date inválida") }
                    if let x = op.desc, x.trimmingCharacters(in: .whitespaces).isEmpty { errs.append("\(p): desc vazia") }
                    if let a = op.acct, !Accounts.all.contains(a) { errs.append("\(p): acct inválida") }
                    if let a = op.amount, !(a > 0) { errs.append("\(p): amount deve ser positivo") }
                    if let c = op.cat, !isCat(c) { errs.append("\(p): categoria \"\(c)\" não existe") }
                }
            case "set_budget":
                if (op.month ?? "").range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) == nil { errs.append("\(p): month deve ser AAAA-MM") }
                if !Categories.all.contains(op.cat ?? "") { errs.append("\(p): categoria \"\(op.cat ?? "")\" não existe") }
                if !(op.amount.map { $0.isFinite } ?? false) { errs.append("\(p): amount inválido") }
            default: errs.append("\(p): op desconhecida")
            }
        }
        return errs
    }

    /// aiApply(): applies a validated proposal. Returns the tool_result text.
    public static func apply(_ d: inout AppData, _ input: JSONObject) -> String {
        var created: [String] = [], edited: [String] = [], deleted: [String] = [], budgets: [String] = [], skipped: [String] = []
        for op in operations(input) {
            switch op.op {
            case "add":
                let isIn = op.type == "entrada", amt = op.amount ?? 0
                let t = Txn(id: d.nextId, date: op.date ?? Day.today(), desc: (op.desc ?? "").trimmingCharacters(in: .whitespaces),
                            acct: op.acct ?? "Revolut", out: isIn ? 0 : amt, in_: isIn ? amt : 0, notes: op.notes ?? "", cat: op.cat ?? "",
                            recurring: op.recurring ?? false, warning: op.aConfirmar ?? false)
                d.txns.append(t); created.append("\(t.id) (\(t.desc))")
            case "update":
                guard let id = op.id, let t = d.txn(id), !t.locked else { skipped.append(op.id.map(String.init) ?? "?"); continue }
                d.update(id) { t in
                    let type = op.type ?? (t.in_ > 0 ? "entrada" : "saida")
                    let amount = op.amount ?? (t.out > 0 ? t.out : t.in_)
                    if let x = op.date { t.date = x }
                    if let x = op.desc { t.desc = x.trimmingCharacters(in: .whitespaces) }
                    if let x = op.acct { t.acct = x }
                    if let x = op.cat { t.cat = x }
                    if let x = op.notes { t.notes = x }
                    if let x = op.aConfirmar { t.warning = x }
                    if let x = op.recurring { t.recurring = x }
                    t.out = type == "saida" ? amount : 0
                    t.in_ = type == "entrada" ? amount : 0
                }
                edited.append(String(id))
            case "delete":
                guard let id = op.id, let t = d.txn(id), !t.locked else { skipped.append(op.id.map(String.init) ?? "?"); continue }
                d.txns.removeAll { $0.id == id }; deleted.append(String(id))
            case "set_budget":
                guard let m = op.month, let c = op.cat, let a = op.amount else { continue }
                d.setBudget(m, c, a); budgets.append("\(m) \(c)=\(money(a))")
            default: break
            }
        }
        var parts = ["O usuário aplicou a proposta."]
        if !created.isEmpty { parts.append("Criadas: " + created.joined(separator: ", ")) }
        if !edited.isEmpty { parts.append("Editadas: " + edited.joined(separator: ", ")) }
        if !deleted.isEmpty { parts.append("Apagadas: " + deleted.joined(separator: ", ")) }
        if !budgets.isEmpty { parts.append("Orçado definido: " + budgets.joined(separator: ", ")) }
        if !skipped.isEmpty { parts.append("Ignoradas (não existem ou estão reconciliadas): " + skipped.joined(separator: ", ")) }
        return parts.joined(separator: "\n")
    }

    // MARK: Changes made outside the chat

    static func hash(_ s: String) -> Int32 { var h: Int32 = 5381; for u in s.utf16 { h = (h &<< 5) &+ h &+ Int32(u) }; return h }
    public struct Seen: Equatable, Sendable {
        public var txns: [Int: Int32]
        public var budgets: [String: Int32]
        public var today: String
    }
    public static func seen(_ d: AppData, today: String) -> Seen {
        var t: [Int: Int32] = [:]; for x in d.txns { t[x.id] = hash(JSON.serialize(.object(x.raw))) }
        var b: [String: Int32] = [:]; for (m, v) in d.rest["budgets"]?.objectValue?.pairs ?? [] { b[m] = hash(JSON.serialize(v)) }
        return Seen(txns: t, budgets: b, today: today)
    }
    /// aiDataChanges(): what changed since the model last saw the data; nil when nothing.
    public static func changes(_ d: AppData, since s: Seen, today: String) -> String? {
        var out: [String] = []
        if today != s.today { out.append("Hoje agora é \(todayLabel(today)).") }
        var added: [Txn] = [], changed: [Txn] = [], ids = Set<Int>()
        for t in d.txns {
            ids.insert(t.id)
            let h = hash(JSON.serialize(.object(t.raw)))
            if let old = s.txns[t.id] { if old != h { changed.append(t) } } else { added.append(t) }
        }
        let removed = s.txns.keys.filter { !ids.contains($0) }.sorted()
        if !added.isEmpty { out.append("Transações novas:\n" + added.map(line).joined(separator: "\n")) }
        if !changed.isEmpty { out.append("Transações alteradas (versão atual):\n" + changed.map(line).joined(separator: "\n")) }
        if !removed.isEmpty { out.append("Transações apagadas (ids): " + removed.map(String.init).joined(separator: ", ")) }
        let bp = d.rest["budgets"]?.objectValue?.pairs ?? []
        let bm = bp.filter { s.budgets[$0.0] != hash(JSON.serialize($0.1)) }
        if !bm.isEmpty {
            out.append("Orçado atualizado: " + bm.map { (m, v) in
                let parts = (v.objectValue?.pairs ?? []).compactMap { (c, x) -> String? in let n = x.doubleValue ?? 0; return n != 0 ? "\(c)=\(money(n))" : nil }
                return "\(m): " + (parts.isEmpty ? "(vazio)" : parts.joined(separator: " ; "))
            }.joined(separator: "\n"))
        }
        if !added.isEmpty || !changed.isEmpty || !removed.isEmpty || !bm.isEmpty {
            out.append("Saldos hoje: \(balancesLine(d, today)). A Alocar: \(money(Ledger.aAlocar(d, today: today))).")
        }
        return out.isEmpty ? nil : out.joined(separator: "\n\n")
    }

    public static func cost(_ usage: JSONObject) -> Double {
        let n = { (k: String) in usage[k]?.doubleValue ?? 0 }
        return (n("input_tokens") * price.input + n("output_tokens") * price.output
                + n("cache_creation_input_tokens") * price.cacheWrite + n("cache_read_input_tokens") * price.cacheRead) / 1_000_000
    }
}
