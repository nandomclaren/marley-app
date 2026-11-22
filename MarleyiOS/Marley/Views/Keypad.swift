import SwiftUI
import UIKit
import Combine
import MarleyCore

/// Qual campo de valor está usando o teclado-calculadora agora.
@MainActor @Observable
final class KeypadController {
    private(set) var activeID: UUID?
    private(set) var text = ""
    private(set) var invalid = false
    private(set) var allowNegative = false
    var tapCount = 0
    @ObservationIgnored private var write: (String) -> Void = { _ in }
    @ObservationIgnored private var onCommit: () -> Void = {}

    var isActive: Bool { activeID != nil }
    var preview: Double? { Calc.evaluate(text) }

    func activate(id: UUID, text: String, allowNegative: Bool, write: @escaping (String) -> Void, onCommit: @escaping () -> Void) {
        if activeID == id { return }
        if isActive { close() }                 // confirma o campo anterior
        hideKeyboard()                          // fecha o teclado do sistema, se houver
        activeID = id
        self.text = text
        self.allowNegative = allowNegative
        self.write = write
        self.onCommit = onCommit
        invalid = false
    }

    enum Key: Hashable { case digit(String), comma, op(String), back, equals }

    func press(_ k: Key) {
        tapCount += 1
        invalid = false
        var t = text
        switch k {
        case .digit(let d): t += d
        case .comma:
            let segment = t.split(whereSeparator: { Calc.operators.contains($0) }).last.map(String.init) ?? ""
            if t.isEmpty || Calc.operators.contains(t.last!) { t += "0," }
            else if !segment.contains(",") { t += "," }
        case .op(let o):
            if t.isEmpty { if o == "−" && allowNegative { t = "−" } }
            else if let last = t.last, Calc.operators.contains(last) || last == "," { t.removeLast(); if !t.isEmpty { t += o } }
            else { t += o }
        case .back: if !t.isEmpty { t.removeLast() }
        case .equals: _ = evaluateInPlace(); return
        }
        text = t
        write(t)
    }

    /// Troca a conta pelo resultado. false se a conta é inválida (ou negativa onde não pode).
    @discardableResult
    func evaluateInPlace() -> Bool {
        if text.isEmpty { return true }
        guard let v = Calc.evaluate(text), allowNegative || v >= 0 else { invalid = true; return false }
        text = Calc.format(v)
        write(text)
        return true
    }

    /// OK: calcula, fecha e avisa o campo. Fica aberto se a conta for inválida.
    func confirm() {
        guard evaluateInPlace() else { return }
        close()
    }
    /// Fecha confirmando (por exemplo, ao abrir o teclado do sistema em outro campo).
    func close() {
        guard isActive else { return }
        if Calc.isExpression(text) { _ = evaluateInPlace() }
        let commit = onCommit
        activeID = nil
        write = { _ in }
        onCommit = {}
        commit()
    }
}

/// Campo de valor que abre o teclado-calculadora. Sem um `keypadHost()` acima, vira um TextField numérico comum.
struct AmountField: View {
    @Environment(KeypadController.self) private var keypad: KeypadController?
    let placeholder: String
    @Binding var text: String
    var allowNegative = false
    var font: Font = .body
    var alignment: TextAlignment = .leading
    var autoActivate = false
    var onCommit: () -> Void = {}
    @State private var id = UUID()

    var body: some View {
        if let keypad {
            let active = keypad.activeID == id
            VStack(alignment: alignment == .trailing ? .trailing : alignment == .center ? .center : .leading, spacing: 2) {
                HStack(spacing: 1) {
                    if alignment != .leading { Spacer(minLength: 0) }
                    Text(text.isEmpty ? placeholder : text)
                        .foregroundStyle(text.isEmpty ? Color.secondary.opacity(0.6) : (active && keypad.invalid ? Color.moneyOut : Color.primary))
                        .lineLimit(1).minimumScaleFactor(0.5)
                    if active { Caret() }
                    if alignment != .trailing { Spacer(minLength: 0) }
                }
                .font(font.monospacedDigit())
                if active, Calc.isExpression(text) {
                    Text(keypad.invalid ? "conta inválida" : keypad.preview.map { "= \(Money.eur($0))" } ?? "…")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(keypad.invalid ? Color.moneyOut : .secondary)
                }
            }
            .contentShape(.rect)
            .onTapGesture { activate(keypad) }
            .onAppear { if autoActivate { activate(keypad) } }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(placeholder)
            .accessibilityValue(text)
        } else {
            TextField(placeholder, text: $text)
                .keyboardType(.decimalPad).font(font.monospacedDigit()).multilineTextAlignment(alignment)
                .onSubmit(onCommit)
        }
    }

    func activate(_ k: KeypadController) {
        let binding = $text
        k.activate(id: id, text: text, allowNegative: allowNegative, write: { binding.wrappedValue = $0 }, onCommit: onCommit)
    }
}

/// Cursor piscando no campo ativo.
private struct Caret: View {
    @State private var on = true
    var body: some View {
        Rectangle().fill(Color.marleyAccent).frame(width: 2, height: 22)
            .opacity(on ? 1 : 0)
            .onAppear { withAnimation(.easeInOut(duration: 0.5).repeatForever()) { on = false } }
    }
}

/// O teclado: dígitos, vírgula, apagar, + − × ÷, = e OK.
struct CalculatorKeypad: View {
    let keypad: KeypadController
    private let rows: [[KeypadController.Key]] = [
        [.digit("7"), .digit("8"), .digit("9"), .op("÷")],
        [.digit("4"), .digit("5"), .digit("6"), .op("×")],
        [.digit("1"), .digit("2"), .digit("3"), .op("−")],
        [.comma, .digit("0"), .back, .op("+")],
    ]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 8) { ForEach(row, id: \.self) { key($0) } }
            }
            HStack(spacing: 8) {
                Button { keypad.press(.equals) } label: { Text("=").frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.glass)
                Button { keypad.confirm() } label: { Text("OK").fontWeight(.semibold).frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.glassProminent)
            }
            .font(.title3)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
        .sensoryFeedback(.selection, trigger: keypad.tapCount)
    }

    func key(_ k: KeypadController.Key) -> some View {
        Button { keypad.press(k) } label: {
            Group {
                switch k {
                case .digit(let d): Text(d)
                case .comma: Text(",")
                case .op(let o): Text(o).foregroundStyle(Color.marleyAccent)
                case .back: Image(systemName: "delete.left")
                case .equals: Text("=")
                }
            }
            .font(.title2.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 48)
        }
        .buttonStyle(.glass)
    }
}

struct KeypadHost: ViewModifier {
    @State private var keypad = KeypadController()
    func body(content: Content) -> some View {
        content
            .environment(keypad)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if keypad.isActive {
                    CalculatorKeypad(keypad: keypad).transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy(duration: 0.25), value: keypad.isActive)
            // um campo de texto comum abriu o teclado do sistema: fecha a calculadora confirmando o valor
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keypad.close() }
            .onDisappear { keypad.close() }
    }
}
extension View {
    /// Coloque no conteúdo de uma tela que tem AmountField: o teclado-calculadora aparece embaixo dela.
    func keypadHost() -> some View { modifier(KeypadHost()) }
}
