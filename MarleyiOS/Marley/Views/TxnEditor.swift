import SwiftUI
import MarleyCore

struct TxnEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let target: EditorTarget

    @State private var isIncome = false
    @State private var amountText = ""
    @State private var desc = ""
    @State private var date = Date()
    @State private var acct = "Revolut"
    @State private var installments = 1
    @State private var recurring = false
    @State private var uncertain = false
    @State private var cat = ""
    @State private var notes = ""
    @State private var deleting: Txn?
    @State private var catTouched = false
    @State private var askScope = false
    @State private var confirmDiscard = false
    @State private var initial: Snapshot?

    /// O que está no formulário, para saber se algo mudou desde que ele abriu.
    struct Snapshot: Equatable {
        var isIncome: Bool, amountText: String, desc: String, date: Date, acct: String, installments: Int
        var recurring: Bool, uncertain: Bool, cat: String, notes: String
    }
    var snapshot: Snapshot {
        Snapshot(isIncome: isIncome, amountText: amountText, desc: desc, date: date, acct: acct, installments: installments,
                 recurring: recurring, uncertain: uncertain, cat: cat, notes: notes)
    }
    var dirty: Bool { initial != nil && snapshot != initial }
    @FocusState private var focus: Field?
    enum Field { case amount, desc }

    var editing: Txn? { if case .edit(let t) = target { return t }; return nil }
    var amount: Double? { parseAmount(amountText).flatMap { $0 > 0 ? $0 : nil } }
    var valid: Bool {
        guard amount != nil, !desc.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return installments <= 1 || Int(((amount ?? 0) * 100).rounded()) >= installments
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Tipo", selection: $isIncome) {
                        Text("Saída").tag(false)
                        Text("Entrada").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                Section {
                    HStack {
                        Text("€").foregroundStyle(.secondary)
                        AmountField(placeholder: installments > 1 ? "Valor total" : "Valor", text: $amountText,
                                    font: .title2.weight(.semibold), autoActivate: editing == nil)
                    }
                    TextField("Descrição", text: $desc).focused($focus, equals: .desc)
                        .submitLabel(.done).onSubmit { focus = nil }
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(suggestions, id: \.self) { s in
                                    Button(displayDescription(s)) { pick(s) }.buttonStyle(.glass).font(.caption)
                                }
                            }
                        }
                    }
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                    Picker("Conta", selection: $acct) { ForEach(Accounts.all, id: \.self) { Text($0).tag($0) } }
                        .pickerStyle(.segmented)
                }
                Section {
                    CategoryPicker(selection: Binding(get: { cat }, set: { cat = $0; catTouched = true }))
                    Toggle("A confirmar", isOn: $uncertain)
                    if editing == nil {
                        Stepper(value: $installments, in: 1...Installments.max) {
                            HStack { Text("Parcelas"); Spacer(); Text(installments == 1 ? "à vista" : "\(installments)×").foregroundStyle(.secondary) }
                        }
                    }
                    Toggle("Recorrente (todo mês)", isOn: $recurring).disabled(installments > 1)
                } footer: { if let hint = installmentHint { Text(hint) } }
                Section { TextField("Notas", text: $notes, axis: .vertical) }
                if let t = editing {
                    Section {
                        Button("Apagar transação", role: .destructive) { deleting = t }
                    } footer: {
                        if t.locked { Text("Reconciliada 🔒") }
                    }
                }
            }
            .keypadHost()
            .keyboardDismissable()
            .navigationTitle(editing == nil ? "Nova transação" : "Editar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { if dirty { confirmDiscard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar") { save() }.disabled(!valid) }
            }
            .deleteConfirmation(for: $deleting) { dismiss() }
            .confirmationDialog("Transação recorrente", isPresented: $askScope, titleVisibility: .visible) {
                if let t = current {
                    let future = Recurring.others(store.data, t, .thisAndFuture).count
                    let all = Recurring.others(store.data, t, .all).count
                    Button("Só esta") { commit(.this) }
                    if future > 0 { Button("Esta e as futuras (\(future + 1))") { commit(.thisAndFuture) } }
                    Button("Todas (\(all + 1))") { commit(.all) }
                    Button("Cancelar", role: .cancel) {}
                }
            } message: {
                Text("Aplicar a alteração a quais lançamentos de \"\(displayDescription(current?.desc ?? ""))\"? Só os campos que você mudou passam para os outros meses. Reconciliadas 🔒 não mudam.")
            }
            .onAppear(perform: load)
            .confirmDismiss(when: dirty) { confirmDiscard = true }
            .confirmationDialog("Descartar alterações?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Descartar", role: .destructive) { dismiss() }
                Button("Continuar editando", role: .cancel) {}
            } message: { Text("O que você preencheu nesta transação será perdido.") }
            .onChange(of: installments) { _, n in if n > 1 { recurring = false } }
        }
    }

    var installmentHint: String? {
        guard installments > 1 else { return nil }
        guard let a = amount else { return "\(installments) parcelas mensais; a 1ª cai no mês da compra." }
        let p = Installments.plan(total: a, count: installments, date: Day.string(date))
        let each = Money.eur(p[1].amount)
        return p[0].amount == p[1].amount ? "\(installments)× \(each), a 1ª neste mês." : "\(installments)× \(each) (1ª \(Money.eur(p[0].amount))), a 1ª neste mês."
    }

    /// Past descriptions starting with what was typed, most recent first (like the web autocomplete).
    var suggestions: [String] {
        let typed = displayDescription(desc).lowercased()
        guard typed.count >= 3, focus == .desc else { return [] }
        return Array(store.pastDescriptions.lazy.filter { $0.bare.hasPrefix(typed) && $0.bare != typed }.prefix(6).map { $0.desc })
    }
    func pick(_ s: String) {
        desc = s
        if !catTouched, let last = store.lastCategoryByDesc[s] { cat = last }
        focus = nil
    }

    func load() {
        defer { if initial == nil { initial = snapshot } }
        guard initial == nil else { return } // onAppear pode repetir; só carrega uma vez
        if let t = editing {
            isIncome = t.isIncome
            amountText = t.amount < 0.005 ? "" : String(format: "%.2f", t.amount).replacingOccurrences(of: ".", with: ",")
            desc = t.desc; date = Day.date(t.date) ?? Date(); acct = Accounts.all.contains(t.acct) ? t.acct : "Revolut"
            recurring = t.recurring || t.style == "fixed"; uncertain = t.isUncertain; cat = t.cat; notes = t.notes; catTouched = true
        } else {
            if case .new(let a?) = target { acct = a }
        }
    }

    /// A versão atual da transação editada (pode ter mudado por sync desde que o editor abriu).
    var current: Txn? { editing.map { store.data.txn($0.id) ?? $0 } }

    func save() {
        if let t = current, Recurring.hasOthers(store.data, t) { askScope = true; return }
        commit(.this)
    }

    func commit(_ scope: RecurringScope) {
        guard let amount else { return }
        let d = desc.trimmingCharacters(in: .whitespaces), n = notes.trimmingCharacters(in: .whitespaces), ds = Day.string(date)
        if let t = current {
            store.updateTransaction(t, with: TxnEdit(date: ds, desc: d, acct: acct, amount: amount, isIncome: isIncome, cat: cat, notes: n,
                                                     recurring: recurring, uncertain: uncertain), scope: scope)
        } else {
            store.addTransaction(date: ds, desc: d, acct: acct, amount: amount, isIncome: isIncome, cat: cat, notes: n,
                                 recurring: recurring, uncertain: uncertain, installments: installments)
        }
        dismiss()
    }
}
