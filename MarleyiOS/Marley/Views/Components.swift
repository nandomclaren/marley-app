import SwiftUI
import UIKit
import MarleyCore

extension Color {
    static let marleyAccent = Color(red: 0x58 / 255, green: 0x56 / 255, blue: 0xD6 / 255)
    static let moneyIn = Color(red: 0.13, green: 0.62, blue: 0.33)
    static let moneyOut = Color(red: 0.83, green: 0.24, blue: 0.32)
}

/// Amount with sign and color: −12,50 € in red, +100,00 € in green.
struct AmountText: View {
    let value: Double
    var font: Font = .body
    var body: some View {
        Text(Money.eur(value, signed: true))
            .font(font.monospacedDigit())
            .foregroundStyle(value < -0.004 ? Color.moneyOut : value > 0.004 ? Color.moneyIn : .secondary)
    }
}

/// Toolbar menu to switch month. Shows the month name; February is the app's start month.
struct MonthMenu: View {
    @Environment(AppStore.self) private var store
    var hideFebruary = false
    var body: some View {
        Menu {
            Picker("Mês", selection: Binding(get: { store.selectedMonth }, set: { store.selectMonth($0) })) {
                ForEach(store.data.months.reversed().filter { !hideFebruary || $0 != Ledger.startMonth }, id: \.self) { m in
                    Text(Day.monthLabel(m, withYear: true)).tag(m)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(Day.monthLabel(store.selectedMonth)).fontWeight(.semibold)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
        }
    }
}

/// Cloud button showing sync state; tap to sync.
struct SyncButton: View {
    @Environment(AppStore.self) private var store
    @State private var showDetail = false
    var body: some View {
        Button {
            switch store.syncStatus {
            case .unconfigured: store.showSettings = true
            case .error, .blocked: showDetail = true
            default: Task { await store.syncNow() }
            }
        } label: {
            switch store.syncStatus {
            case .syncing: ProgressView()
            case .synced: Image(systemName: "checkmark.icloud")
            case .idle: Image(systemName: "icloud")
            case .unconfigured: Image(systemName: "icloud.slash")
            case .error, .blocked: Image(systemName: "exclamationmark.icloud").foregroundStyle(.orange)
            }
        }
        .accessibilityLabel("Sincronizar")
        .alert(alertTitle, isPresented: $showDetail) {
            Button("Tentar de novo") { Task { await store.syncNow() } }
            Button("OK", role: .cancel) {}
        } message: { Text(alertMessage) }
    }
    var alertTitle: String { if case .blocked = store.syncStatus { return "Envio bloqueado" }; return "Problema na sincronização" }
    var alertMessage: String {
        switch store.syncStatus {
        case .error(let m): return m
        case .blocked(let issues): return "A proteção de dados não enviou porque:\n" + issues.map { "• \($0)" }.joined(separator: "\n") + "\n\nToque em Tentar de novo para rever."
        default: return ""
        }
    }
}

struct SettingsButton: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Button { store.showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Configurações")
    }
}

/// Small stat block for the top of a screen.
struct StatCard: View {
    let title: String
    let value: Double
    var signed = false
    var tint: Color? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(Money.eur(value, signed: signed))
                .font(.headline.monospacedDigit())
                .foregroundStyle(tint ?? (value < -0.004 ? Color.moneyOut : .primary))
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }
}

/// Category picker grouped like the web app, with "no category".
struct CategoryPicker: View {
    @Binding var selection: String
    var body: some View {
        Picker("Categoria", selection: $selection) {
            Text("Sem categoria").tag("")
            ForEach(Categories.groups, id: \.group) { g in
                Section(g.group) { ForEach(g.cats, id: \.self) { Text($0).tag($0) } }
            }
        }
        .pickerStyle(.navigationLink)
    }
}

/// Renders the model's light markdown (bold, inline code, lists) as text.
struct MarkdownText: View {
    let text: String
    var body: some View {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let cleaned = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var l = String(line)
            if l.hasPrefix("- ") || l.hasPrefix("* ") { l = "• " + l.dropFirst(2) }
            while l.hasPrefix("#") { l.removeFirst() }
            return l
        }.joined(separator: "\n")
        Text((try? AttributedString(markdown: cleaned, options: opts)) ?? AttributedString(cleaned))
    }
}

/// Fecha o teclado (qualquer campo em foco).
@MainActor func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

extension View {
    /// Teclado sempre fechável: botão OK acima do teclado e arrastar a lista para baixo.
    func keyboardDismissable() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("OK") { hideKeyboard() }.fontWeight(.semibold)
                }
            }
    }
}

/// Valor digitado num campo, já com a conta feita ("200-100" → 100). nil se incompleto/inválido.
func parseAmount(_ s: String) -> Double? { Calc.evaluate(s) }
