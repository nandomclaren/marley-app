import SwiftUI
import MarleyCore

struct ContasView: View {
    @Environment(AppStore.self) private var store
    @State private var acct = "Revolut"
    @State private var hideCleared = false
    @State private var editor: EditorTarget?
    @State private var clearing: Txn?
    @State private var deleting: Txn?
    @State private var reconciling = false

    var body: some View {
        let today = store.today
        let s = store.accountSummary(acct)
        let rows = store.accountRows(acct, store.selectedMonth).filter { !hideCleared || (!$0.txn.cleared && !$0.txn.locked) }
        let future = rows.filter { $0.txn.date > today }.reversed()
        let past = rows.filter { $0.txn.date <= today }.reversed()
        NavigationStack {
            List {
                Section {
                    Picker("Conta", selection: $acct) { ForEach(Accounts.all, id: \.self) { Text("\(Accounts.icon($0)) \($0)").tag($0) } }
                        .pickerStyle(.segmented)
                    HStack(spacing: 10) {
                        StatCard(title: "Working", value: s.working)
                        StatCard(title: "Compensado", value: s.cleared, tint: .moneyIn)
                        StatCard(title: "Pendente", value: s.uncleared, signed: true)
                    }
                }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                if !future.isEmpty {
                    Section("Próximos") { ForEach(Array(future)) { r in row(r) } }
                }
                Section(hideCleared ? "Pendentes" : "Transações") {
                    ForEach(Array(past)) { r in row(r) }
                    if past.isEmpty { Text("Nada neste mês.").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle(acct)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { MonthMenu() }
                ToolbarItem(placement: .topBarLeading) { SyncButton() }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button { reconciling = true } label: { Label("Reconciliar \(acct)", systemImage: "scale.3d") }
                        Toggle(isOn: $hideCleared) { Label("Esconder compensadas", systemImage: "eye.slash") }
                    } label: { Image(systemName: "ellipsis") }
                    Button { editor = .new(acct: acct) } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await store.syncNow() }
            .sheet(item: $editor) { TxnEditor(target: $0) }
            .sheet(item: $clearing) { ClearOnDateSheet(txn: $0) }
            .sheet(isPresented: $reconciling) { ReconcileSheet(acct: acct) { hideCleared = true } }
            .deleteConfirmation(for: $deleting)
        }
    }

    func row(_ r: Ledger.RunningRow) -> some View {
        TxnRow(txn: r.txn, balance: r.total)
            .contentShape(.rect)
            .onTapGesture { editor = .edit(r.txn) }
            .swipeActions(edge: .leading) {
                if !r.txn.locked {
                    Button { if !store.toggleCleared(r.txn.id) { clearing = r.txn } } label: {
                        Label(r.txn.cleared ? "Descompensar" : "Compensar", systemImage: r.txn.cleared ? "circle" : "checkmark.circle")
                    }.tint(.moneyIn)
                }
            }
            .swipeActions(edge: .trailing) { Button(role: .destructive) { deleting = r.txn } label: { Label("Apagar", systemImage: "trash") } }
    }
}

/// Reconciliation, same steps as the web: confirm the cleared balance, or enter the bank's and add a correction.
struct ReconcileSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let acct: String
    var onDone: () -> Void
    @State private var step = 1
    @State private var bankText = ""
    @State private var resultText = ""

    var body: some View {
        let cleared = Ledger.clearedBalance(store.data, acct, today: store.today)
        NavigationStack {
            VStack(spacing: 20) {
                switch step {
                case 1:
                    Text("Saldo compensado da \(acct)").font(.headline).foregroundStyle(.secondary)
                    Text(Money.eur(cleared)).font(.system(size: 40, weight: .bold).monospacedDigit())
                    Text("Bate com o saldo do banco agora?").foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button("Não") { step = 2 }.buttonStyle(.glass).controlSize(.large)
                        Button("Sim, bate") {
                            store.reconcileConfirmed(acct)
                            resultText = "Saldo confirmado: \(Money.eur(cleared)). As transações compensadas foram bloqueadas 🔒."
                            step = 3
                        }.buttonStyle(.glassProminent).controlSize(.large)
                    }
                case 2:
                    Text("Qual é o saldo no banco?").font(.headline)
                    TextField("0,00", text: $bankText).keyboardType(.numbersAndPunctuation)
                        .font(.system(size: 34, weight: .bold).monospacedDigit()).multilineTextAlignment(.center)
                    if let v = parseAmount(bankText) {
                        let diff = v - cleared
                        Text(abs(diff) < 0.005 ? "Sem diferença." : "Vai criar uma correção de \(Money.eur(diff, signed: true)).").foregroundStyle(.secondary)
                    }
                    Button("Reconciliar") {
                        guard let v = parseAmount(bankText) else { return }
                        let diff = v - cleared
                        store.reconcile(acct, bankBalance: v)
                        resultText = abs(diff) < 0.005 ? "Reconciliado." : "Correção de \(Money.eur(diff, signed: true)) adicionada e transações bloqueadas 🔒."
                        step = 3
                    }
                    .buttonStyle(.glassProminent).controlSize(.large).disabled(parseAmount(bankText) == nil)
                default:
                    Text("✨🎊✨").font(.largeTitle)
                    Text(resultText).multilineTextAlignment(.center)
                    Button("Fechar") { onDone(); dismiss() }.buttonStyle(.glassProminent).controlSize(.large)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .keyboardDismissable()
            .navigationTitle("Reconciliar \(acct)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { if step < 3 { Button("Cancelar") { dismiss() } } } }
        }
        .presentationDetents([.medium, .large])
    }
}
