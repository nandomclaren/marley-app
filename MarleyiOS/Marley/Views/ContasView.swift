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
    @State private var showUpcoming = false

    var body: some View {
        let today = store.today
        let s = store.accountSummary(acct)
        let rows = store.accountRows(acct, store.selectedMonth).filter { !hideCleared || (!$0.txn.cleared && !$0.txn.locked) }
        let future = rows.filter { $0.txn.date > today }.reversed()
        let past = rows.filter { $0.txn.date <= today }.reversed()
        let days = Dictionary(grouping: past, by: { $0.txn.date })
        NavigationStack {
            List {
                Section {
                    Picker("Conta", selection: $acct) { ForEach(Accounts.all, id: \.self) { Text("\(Accounts.icon($0)) \($0)").tag($0) } }
                        .pickerStyle(.segmented)
                    HStack(spacing: 10) {
                        StatCard(title: "Working Balance", value: s.working)
                        StatCard(title: "✓ Cleared", value: s.cleared, tint: .moneyIn)
                        StatCard(title: "Uncleared", value: s.uncleared, signed: true)
                    }
                }
                .listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                if !future.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showUpcoming) {
                            ForEach(Array(future)) { r in row(r) }
                        } label: {
                            Label("Próximos — \(future.count) agendado\(future.count == 1 ? "" : "s")", systemImage: "calendar.badge.clock")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                // por dia, como no Fluxo
                ForEach(days.keys.sorted(by: >), id: \.self) { day in
                    Section(dayTitle(day, today: today)) { ForEach(days[day]!) { r in row(r) } }
                }
                if past.isEmpty {
                    Section { Text(hideCleared ? "Nenhuma transação uncleared neste mês." : "Nada neste mês.").foregroundStyle(.secondary) }
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
                        Toggle(isOn: $hideCleared) { Label("Esconder cleared", systemImage: "eye.slash") }
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
                        Label(r.txn.cleared ? "Uncleared" : "Cleared", systemImage: r.txn.cleared ? "circle" : "checkmark.circle")
                    }.tint(.moneyIn)
                }
            }
            // sem role destrutivo: só apaga depois da confirmação
            .swipeActions(edge: .trailing) { Button { deleting = r.txn } label: { Label("Apagar", systemImage: "trash") }.tint(.red) }
    }
}

/// Reconciliação, mesmos passos do web: confirma o saldo cleared, ou informa o do banco e cria uma correção.
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
            Form {
                switch step {
                case 1:
                    Section {
                        LabeledContent("Saldo cleared", value: Money.eur(cleared)).font(.title3.weight(.semibold))
                    } footer: { Text("Bate com o saldo da \(acct) no banco agora?") }
                    Section {
                        Button("Sim, bate") {
                            store.reconcileConfirmed(acct)
                            resultText = "Saldo confirmado: \(Money.eur(cleared)). As transações cleared agora estão reconciliadas 🔒."
                            step = 3
                        }
                        Button("Não, o banco mostra outro valor") { step = 2 }
                    }
                case 2:
                    Section {
                        LabeledContent("Saldo cleared no Marley", value: Money.eur(cleared))
                        HStack {
                            Text("Saldo no banco")
                            Spacer()
                            AmountField(placeholder: "0,00", text: $bankText, allowNegative: true, font: .title3.weight(.semibold),
                                        alignment: .trailing, autoActivate: true)
                                .frame(maxWidth: 180)
                        }
                    } footer: {
                        if let v = parseAmount(bankText) {
                            let diff = v - cleared
                            Text(abs(diff) < 0.005 ? "Sem diferença." : "Vai criar uma transação de correção de \(Money.eur(diff, signed: true)).")
                        }
                    }
                    Section {
                        Button("Reconciliar") {
                            guard let v = parseAmount(bankText) else { return }
                            let diff = v - cleared
                            store.reconcile(acct, bankBalance: v)
                            resultText = abs(diff) < 0.005 ? "Conta reconciliada 🔒." : "Correção de \(Money.eur(diff, signed: true)) adicionada. Conta reconciliada 🔒."
                            step = 3
                        }
                        .disabled(parseAmount(bankText) == nil)
                    }
                default:
                    Section {
                        VStack(spacing: 10) {
                            Text("✨🎊✨").font(.largeTitle)
                            Text(resultText).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                }
            }
            .keypadHost()
            .keyboardDismissable()
            .navigationTitle("Reconciliar \(acct)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: step < 3 ? .cancellationAction : .confirmationAction) {
                    Button(step < 3 ? "Cancelar" : "Fechar") { if step == 3 { onDone() }; dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
