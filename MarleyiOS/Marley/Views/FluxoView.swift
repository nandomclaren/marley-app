import SwiftUI
import MarleyCore

/// What the editor sheet is editing.
enum EditorTarget: Identifiable {
    case new(acct: String?)
    case edit(Txn)
    var id: String { switch self { case .new: return "new"; case .edit(let t): return "t\(t.id)" } }
}

struct FluxoView: View {
    @Environment(AppStore.self) private var store
    @State private var editor: EditorTarget?
    @State private var clearing: Txn?
    @State private var deleting: Txn?
    @State private var showUpcoming = false

    var body: some View {
        let rows = store.monthRows(store.selectedMonth)
        let today = store.today
        // Mais distante no topo, mais próxima embaixo (colada no dia de hoje), como no web e no Android.
        let upcoming = Array(rows.filter { $0.txn.date > today }.reversed())
        let past = rows.filter { $0.txn.date <= today }.reversed()
        let days = Dictionary(grouping: past, by: { $0.txn.date })
        NavigationStack {
            List {
                Section { summary(rows) }
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                if !upcoming.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showUpcoming) {
                            ForEach(upcoming) { r in row(r) }
                        } label: {
                            Label("Próximos — \(upcoming.count) agendado\(upcoming.count == 1 ? "" : "s")", systemImage: "calendar.badge.clock")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                ForEach(days.keys.sorted(by: >), id: \.self) { day in
                    Section(dayTitle(day, today: today)) { ForEach(days[day]!) { r in row(r) } }
                }
                if rows.isEmpty { ContentUnavailableView("Nenhuma transação neste mês", systemImage: "tray") }
            }
            .navigationTitle(Day.monthLabel(store.selectedMonth))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { MonthMenu() }
                ToolbarItem(placement: .topBarLeading) { SyncButton() }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    SettingsButton()
                    Button { editor = .new(acct: nil) } label: { Image(systemName: "plus") }.accessibilityLabel("Nova transação")
                }
            }
            .refreshable { await store.syncNow() }
            .sheet(item: $editor) { TxnEditor(target: $0) }
            .sheet(item: $clearing) { ClearOnDateSheet(txn: $0) }
            .deleteConfirmation(for: $deleting)
        }
    }

    func summary(_ rows: [Ledger.RunningRow]) -> some View {
        let bal = store.balancesToday.values.reduce(0, +)
        let inn = rows.reduce(0) { $0 + $1.txn.in_ }, out = rows.reduce(0) { $0 + $1.txn.out }
        return HStack(spacing: 10) {
            StatCard(title: "Saldo hoje", value: bal)
            StatCard(title: "Entradas", value: inn, tint: .moneyIn)
            StatCard(title: "Saídas", value: -out)
        }
    }

    func row(_ r: Ledger.RunningRow) -> some View {
        TxnRow(txn: r.txn, balance: r.total)
            .contentShape(.rect)
            .onTapGesture { editor = .edit(r.txn) }
            .swipeActions(edge: .leading) { clearAction(r.txn) }
            .swipeActions(edge: .trailing) {
                Button { deleting = r.txn } label: { Label("Apagar", systemImage: "trash") }.tint(.red) // sem role destrutivo: só apaga depois da confirmação
            }
    }

    @ViewBuilder func clearAction(_ t: Txn) -> some View {
        if !t.locked {
            Button {
                if !store.toggleCleared(t.id) { clearing = t }
            } label: {
                Label(t.cleared ? "Uncleared" : "Cleared", systemImage: t.cleared ? "circle" : "checkmark.circle")
            }
            .tint(.moneyIn)
        }
    }

}

struct TxnRow: View {
    let txn: Txn
    var balance: Double? = nil

    var body: some View {
        let missingCat = txn.out > 0 && txn.cat.isEmpty
        HStack(spacing: 12) {
            Text(missingCat ? "⚠️" : (txn.cat.isEmpty ? (txn.isIncome ? "💰" : "•") : Categories.emoji(txn.cat)))
                .font(.title3)
                .frame(width: 38, height: 38)
                .background(.background.secondary, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(displayDescription(txn.desc)).lineLimit(1)
                    if txn.isUncertain { Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange) }
                    if txn.isRecurringKind { Image(systemName: "repeat").font(.caption2).foregroundStyle(.secondary) }
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                AmountText(value: txn.net, font: .callout.weight(.semibold))
                HStack(spacing: 4) {
                    if let balance { Text(Money.eur(balance)).font(.caption2.monospacedDigit()).foregroundStyle(balance < 0 ? Color.moneyOut : .secondary) }
                    statusIcon
                }
            }
        }
        .padding(.vertical, 2)
    }

    var subtitle: String {
        var parts = [txn.acct]
        if !txn.cat.isEmpty { parts.append(Categories.name(txn.cat)) } else if txn.out > 0 { parts.append("sem categoria") }
        if !txn.notes.isEmpty { parts.append(txn.notes) }
        return parts.joined(separator: " · ")
    }
    @ViewBuilder var statusIcon: some View {
        if txn.locked { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary) }
        else if txn.cleared { Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(Color.moneyIn) }
    }
}

/// Clearing a future transaction asks for the real date (≤ today), like the web app.
struct ClearOnDateSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let txn: Txn
    @State private var date = Date()
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Data", selection: $date, in: ...Date(), displayedComponents: .date)
                } footer: {
                    Text("\(displayDescription(txn.desc)) tem data futura (\(Day.short(txn.date))). Para marcá-la como cleared, escolha uma nova data (hoje ou anterior).")
                }
            }
            .navigationTitle("Trazer para o presente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Confirmar") { store.clear(txn.id, on: Day.string(date)); dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Delete with the installment choice ("só esta" / "esta e as seguintes"); reconciled parts are never deleted.
struct DeleteConfirmation: ViewModifier {
    @Environment(AppStore.self) private var store
    @Binding var txn: Txn?
    var onDeleted: () -> Void = {}

    func body(content: Content) -> some View {
        let following = txn.map { Installments.following(store.data, $0).filter { !$0.locked } } ?? []
        let recFuture = txn.map { Recurring.others(store.data, $0, .thisAndFuture).count } ?? 0
        let recAll = txn.map { Recurring.others(store.data, $0, .all).count } ?? 0
        content.confirmationDialog(title, isPresented: Binding(get: { txn != nil }, set: { if !$0 { txn = nil } }), titleVisibility: .visible, presenting: txn) { t in
            if following.isEmpty && recAll > 0 {
                Button("Só esta", role: .destructive) { store.deleteRecurring(t, scope: .this); onDeleted() }
                if recFuture > 0 { Button("Esta e as futuras (\(recFuture + 1))", role: .destructive) { store.deleteRecurring(t, scope: .thisAndFuture); onDeleted() } }
                Button("Todas (\(recAll + (t.locked ? 0 : 1)))", role: .destructive) { store.deleteRecurring(t, scope: .all); onDeleted() }
            } else if following.isEmpty {
                Button("Apagar", role: .destructive) { store.delete([t.id]); onDeleted() }
            } else {
                Button("Só esta", role: .destructive) { store.delete([t.id]); onDeleted() }
                Button("Esta e as seguintes (\(following.count + 1))", role: .destructive) { store.delete(Set([t.id] + following.map(\.id))); onDeleted() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: { t in
            if let p = Installments.parse(t.desc), !following.isEmpty { Text("\"\(displayDescription(p.base))\" é a parcela \(p.i) de \(p.n).") }
            else if recAll > 0 { Text("É uma transação recorrente. \"Esta e as futuras\" e \"Todas\" impedem que ela seja recriada nos próximos meses. Reconciliadas 🔒 nunca são apagadas.") }
            else if t.locked { Text("Esta transação está reconciliada 🔒.") }
        }
    }
    var title: String { txn.map { "Apagar \(displayDescription($0.desc))?" } ?? "" }
}
extension View {
    func deleteConfirmation(for txn: Binding<Txn?>, onDeleted: @escaping () -> Void = {}) -> some View {
        modifier(DeleteConfirmation(txn: txn, onDeleted: onDeleted))
    }
}
