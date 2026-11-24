import SwiftUI
import MarleyCore

struct BudgetView: View {
    @Environment(AppStore.self) private var store
    @State private var moving = false

    var body: some View {
        let m = store.selectedMonth
        let lines = store.categoryLines(m)
        let byCat = Dictionary(uniqueKeysWithValues: lines.map { ($0.cat, $0) })
        let attention = lines.filter { $0.available < -0.005 }
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        StatCard(title: "A Alocar", value: store.aAlocarToday, tint: .marleyAccent)
                        HStack(spacing: 10) {
                            StatCard(title: "Orçado", value: lines.reduce(0) { $0 + $1.budgeted })
                            StatCard(title: "Gasto", value: lines.reduce(0) { $0 + $1.spent })
                            StatCard(title: "Disponível", value: lines.reduce(0) { $0 + $1.available })
                        }
                    }
                }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                if !attention.isEmpty {
                    Section("Precisa de atenção") { ForEach(attention) { line($0) } }
                }
                ForEach(Categories.groups, id: \.group) { g in
                    let gl = g.cats.compactMap { byCat[$0] }
                    Section {
                        ForEach(gl) { line($0) }
                    } header: {
                        HStack {
                            Text(g.group)
                            Spacer()
                            Text(Money.eur(gl.reduce(0) { $0 + $1.available })).monospacedDigit()
                        }
                    }
                }
            }
            .navigationTitle("Budget")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { CategoryDetailView(cat: $0) }
            .toolbar {
                ToolbarItem(placement: .principal) { MonthMenu() }
                ToolbarItem(placement: .topBarLeading) { SyncButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { moving = true } label: { Image(systemName: "arrow.left.arrow.right") }.accessibilityLabel("Mover dinheiro")
                }
            }
            .refreshable { await store.syncNow() }
            .sheet(isPresented: $moving) { MoveMoneySheet() }
        }
    }

    func line(_ l: Ledger.CategoryLine) -> some View {
        NavigationLink(value: l.cat) {
            HStack(spacing: 12) {
                Text(Categories.emoji(l.cat)).font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Categories.name(l.cat)).lineLimit(1)
                    Text("Orçado \(Money.eur(l.budgeted)) · Gasto \(Money.eur(l.spent))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                AvailablePill(value: l.available, funded: l.carry + l.budgeted)
            }
        }
    }
}

/// Same color rules as availClass() in the web app.
struct AvailablePill: View {
    let value: Double
    let funded: Double
    var body: some View {
        let color = availableColor(value, funded: funded)
        Text(Money.eur(value))
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 10).padding(.vertical, 4)
            .foregroundStyle(abs(value) < 0.005 ? Color.secondary : color)
            .background(color.opacity(0.15), in: .capsule)
    }
}

struct CategoryDetailView: View {
    @Environment(AppStore.self) private var store
    let cat: String
    @State private var budgetText = ""
    @State private var editor: EditorTarget?

    var body: some View {
        let m = store.selectedMonth
        let line = store.categoryLines(m).first { $0.cat == cat }!
        let txns = Ledger.sorted(store.data.txns.filter { $0.cat == cat && $0.month == m }).reversed()
        let byDesc = Dictionary(grouping: txns, by: { displayDescription($0.desc) })
            .map { DescSum(desc: $0.key, total: $0.value.reduce(0) { acc, t in acc + t.net }, count: $0.value.count) }
            .sorted { $0.total < $1.total }
        List {
            Section {
                VStack(spacing: 6) {
                    Text("Disponível").font(.caption).foregroundStyle(.secondary)
                    Text(Money.eur(line.available)).font(.system(size: 36, weight: .bold).monospacedDigit())
                        .foregroundStyle(line.available < -0.005 ? Color.moneyOut : .primary)
                }
                .frame(maxWidth: .infinity)
                LabeledContent("Carregado dos meses anteriores", value: Money.eur(line.carry))
                HStack {
                    Text("Orçado em \(Day.monthLabel(m))")
                    Spacer()
                    AmountField(placeholder: "0,00", text: $budgetText, allowNegative: true, alignment: .trailing, onCommit: saveBudget)
                        .frame(maxWidth: 160)
                }
                LabeledContent("Gasto", value: Money.eur(line.spent))
            }
            if byDesc.count > 1 {
                Section("Por descrição") {
                    ForEach(byDesc) { d in
                        HStack { Text(d.desc).lineLimit(1); if d.count > 1 { Text("×\(d.count)").font(.caption).foregroundStyle(.secondary) }; Spacer(); AmountText(value: d.total, font: .callout) }
                    }
                }
            }
            Section("Transações") {
                ForEach(Array(txns)) { t in TxnRow(txn: t).contentShape(.rect).onTapGesture { editor = .edit(t) } }
                if txns.isEmpty { Text("Nenhuma neste mês.").foregroundStyle(.secondary) }
            }
        }
        .keypadHost()
        .keyboardDismissable()
        .navigationTitle(cat)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { budgetText = fmt(line.budgeted) }
        .onChange(of: store.selectedMonth) { _, _ in budgetText = fmt(store.data.budget(store.selectedMonth, cat)) }
        .sheet(item: $editor) { TxnEditor(target: $0) }
    }
    /// Zero fica vazio (o placeholder "0,00" aparece em cinza), para digitar direto sem apagar antes.
    func fmt(_ v: Double) -> String { abs(v) < 0.005 ? "" : String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",") }
    func saveBudget() {
        let trimmed = budgetText.trimmingCharacters(in: .whitespaces)
        guard let v = trimmed.isEmpty ? 0 : parseAmount(trimmed) else { budgetText = fmt(store.data.budget(store.selectedMonth, cat)); return }
        store.setBudget(store.selectedMonth, cat, v)
        budgetText = fmt(v)
    }
}

struct DescSum: Identifiable { let desc: String; let total: Double; let count: Int; var id: String { desc } }

struct MoveMoneySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var from = Categories.all[0]
    @State private var to = Categories.all[1]
    @State private var amountText = ""
    var body: some View {
        let amount = parseAmount(amountText) ?? 0
        NavigationStack {
            Form {
                Section {
                    Picker("De", selection: $from) { ForEach(Categories.all, id: \.self) { Text($0).tag($0) } }
                    Picker("Para", selection: $to) { ForEach(Categories.all, id: \.self) { Text($0).tag($0) } }
                    AmountField(placeholder: "Valor", text: $amountText, autoActivate: true)
                } footer: { Text("Move orçado de \(Day.monthLabel(store.selectedMonth)) entre categorias.") }
            }
            .keypadHost()
            .keyboardDismissable()
            .navigationTitle("Mover dinheiro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mover") { store.moveMoney(from: from, to: to, amount: amount); dismiss() }.disabled(from == to || amount <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
