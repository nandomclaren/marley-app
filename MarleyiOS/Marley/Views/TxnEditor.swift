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
                        TextField(installments > 1 ? "Valor total" : "Valor", text: $amountText)
                            .keyboardType(.decimalPad).font(.title2.weight(.semibold).monospacedDigit())
                            .focused($focus, equals: .amount)
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
                        if t.locked { Text("Reconciliada com o banco 🔒") }
                    }
                }
            }
            .keyboardDismissable()
            .navigationTitle(editing == nil ? "Nova transação" : "Editar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Salvar") { save() }.disabled(!valid) }
            }
            .deleteConfirmation(for: $deleting) { dismiss() }
            .onAppear(perform: load)
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
        if let t = editing {
            isIncome = t.isIncome; amountText = String(format: "%.2f", t.amount).replacingOccurrences(of: ".", with: ",")
            desc = t.desc; date = Day.date(t.date) ?? Date(); acct = Accounts.all.contains(t.acct) ? t.acct : "Revolut"
            recurring = t.recurring || t.style == "fixed"; uncertain = t.isUncertain; cat = t.cat; notes = t.notes; catTouched = true
        } else {
            if case .new(let a?) = target { acct = a }
            focus = .amount
        }
    }

    func save() {
        guard let amount else { return }
        let d = desc.trimmingCharacters(in: .whitespaces), n = notes.trimmingCharacters(in: .whitespaces), ds = Day.string(date)
        if let t = editing {
            store.updateTransaction(t.id, date: ds, desc: d, acct: acct, amount: amount, isIncome: isIncome, cat: cat, notes: n, recurring: recurring, uncertain: uncertain)
        } else {
            store.addTransaction(date: ds, desc: d, acct: acct, amount: amount, isIncome: isIncome, cat: cat, notes: n,
                                 recurring: recurring, uncertain: uncertain, installments: installments)
        }
        dismiss()
    }
}
