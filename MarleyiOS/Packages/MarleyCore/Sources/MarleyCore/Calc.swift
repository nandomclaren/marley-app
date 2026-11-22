import Foundation

/// Calculadora dos campos de valor: "200-100" → 100. Equivale ao evalMathExpr do web, mas sem executar código:
/// é um parser próprio que só entende números, + − × ÷ (ou - * /), parênteses e vírgula/ponto decimal.
public enum Calc {
    public static let operators: Set<Character> = ["+", "-", "−", "*", "×", "/", "÷"]

    /// nil se a expressão estiver incompleta ou inválida (inclui divisão por zero). Resultado arredondado a centavos.
    public static func evaluate(_ input: String) -> Double? {
        let cleaned = input.filter { !$0.isWhitespace && $0 != "€" }
        guard !cleaned.isEmpty else { return nil }
        var p = Parser(chars: Array(cleaned))
        guard let v = p.expression(), p.i == p.chars.count, v.isFinite else { return nil }
        let r = (v * 100).rounded() / 100
        return r == 0 ? 0 : r // evita -0
    }

    /// Tem alguma conta para fazer (não é só um número)?
    public static func isExpression(_ s: String) -> Bool {
        let t = s.filter { !$0.isWhitespace }
        return t.dropFirst().contains { operators.contains($0) } || t.contains("(")
    }

    /// Formato dos campos: "100,00".
    public static func format(_ v: Double) -> String { String(format: "%.2f", v).replacingOccurrences(of: ".", with: ",") }

    struct Parser {
        let chars: [Character]
        var i = 0
        var peek: Character? { i < chars.count ? chars[i] : nil }

        mutating func expression() -> Double? {
            guard var v = term() else { return nil }
            while let c = peek, c == "+" || c == "-" || c == "−" {
                i += 1
                guard let r = term() else { return nil }
                v = c == "+" ? v + r : v - r
            }
            return v
        }
        mutating func term() -> Double? {
            guard var v = factor() else { return nil }
            while let c = peek, c == "*" || c == "×" || c == "/" || c == "÷" {
                i += 1
                guard let r = factor() else { return nil }
                if c == "/" || c == "÷" { guard r != 0 else { return nil }; v /= r } else { v *= r }
            }
            return v
        }
        mutating func factor() -> Double? {
            guard let c = peek else { return nil }
            if c == "-" || c == "−" { i += 1; return factor().map { -$0 } }
            if c == "+" { i += 1; return factor() }
            if c == "(" {
                i += 1
                guard let v = expression(), peek == ")" else { return nil }
                i += 1
                return v
            }
            return number()
        }
        mutating func number() -> Double? {
            var s = "", seenSep = false
            while let c = peek, c.isNumber || c == "," || c == "." {
                if c == "," || c == "." { if seenSep { return nil }; seenSep = true; s.append(".") } else { s.append(c) }
                i += 1
            }
            guard !s.isEmpty, s != "." else { return nil }
            return Double(s)
        }
    }
}
