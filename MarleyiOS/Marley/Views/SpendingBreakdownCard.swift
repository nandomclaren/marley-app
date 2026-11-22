import SwiftUI
import Charts
import MarleyCore

extension Color {
    init(hex: String) {
        let v = UInt64(hex.dropFirst(hex.hasPrefix("#") ? 1 : 0), radix: 16) ?? 0
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    /// Mesmas cores por grupo do web (GROUP_COLORS), na ordem dos grupos.
    static let groupColors = ["#5B6DCD", "#56C05A", "#F5B731", "#CF5E59", "#8E93D6", "#26C6DA", "#FF7043", "#78909C", "#8D6E63", "#26A69A"].map(Color.init(hex:))
    static func group(_ index: Int) -> Color { groupColors[index % groupColors.count] }
}

/// Gastos do mês por grupo; tocar num grupo (na lista ou na fatia) mostra as subcategorias dele no mesmo card.
struct SpendingBreakdownCard: View {
    @Environment(AppStore.self) private var store
    let month: String
    /// Abre o detalhe de uma subcategoria (a tela do Budget), empilhado na aba atual.
    var openCategory: (String) -> Void = { _ in }
    @State private var group: String?
    @State private var selectedAngle: Double?

    struct Slice: Identifiable { let name: String; let value: Double; let color: Color; var id: String { name } }

    /// Gasto categorizado até hoje (gastos com data futura ficam de fora, como no web).
    var slices: [Slice] {
        let today = store.today
        var by: [String: Double] = [:]
        for t in store.data.txns where t.month == month && !t.cat.isEmpty && t.date <= today {
            guard let gi = Categories.groupIndex(of: t.cat) else { continue }
            if let group { if Categories.groups[gi].group == group { by[t.cat, default: 0] += t.out - t.in_ } }
            else { by[Categories.groups[gi].group, default: 0] += t.out - t.in_ }
        }
        let sorted = by.filter { $0.value > 0.005 }.sorted { $0.value > $1.value }
        if let group, let gi = Categories.groups.firstIndex(where: { $0.group == group }) {
            let base = Color.group(gi), n = max(sorted.count - 1, 1)
            return sorted.enumerated().map { i, kv in Slice(name: kv.key, value: kv.value, color: base.mix(with: .white, by: Double(i) / Double(n) * 0.55)) }
        }
        return sorted.map { kv in Slice(name: kv.key, value: kv.value, color: Color.group(Categories.groups.firstIndex { $0.group == kv.key } ?? 0)) }
    }

    var body: some View {
        let s = slices
        let total = s.reduce(0) { $0 + $1.value }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if group != nil {
                    Button { withAnimation(.snappy) { group = nil } } label: {
                        Label("Todos", systemImage: "chevron.left").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.glass).controlSize(.small)
                }
                Label(group ?? "Gastos de \(Day.monthLabel(month))", systemImage: "chart.pie.fill")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.marleyAccent).lineLimit(1)
            }
            Text(Money.eur(total)).font(.system(size: 32, weight: .bold).monospacedDigit())
                .contentTransition(.numericText())
            if total > 0 {
                Chart(s) { x in
                    SectorMark(angle: .value("Gasto", x.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .cornerRadius(4)
                        .foregroundStyle(x.color)
                }
                .chartAngleSelection(value: $selectedAngle)
                .frame(height: 220)
                .overlay {
                    VStack(spacing: 2) {
                        Text(group == nil ? "Toque num grupo" : "Toque para ver detalhes")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(s) { x in row(x, total: total) }
            } else {
                Text(group == nil ? "Nenhum gasto neste mês." : "Nenhum gasto neste grupo.").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: .rect(cornerRadius: 20))
        .onChange(of: selectedAngle) { _, angle in
            // fatia da pizza geral abre o grupo; fatia de subcategoria abre o detalhe dela
            guard let angle else { return }
            var acc = 0.0
            for x in s {
                acc += x.value
                if angle <= acc {
                    if group == nil { withAnimation(.snappy) { group = x.name } } else { openCategory(x.name) }
                    break
                }
            }
            selectedAngle = nil
        }
        .onChange(of: month) { _, _ in group = nil }
    }

    @ViewBuilder func row(_ x: Slice, total: Double) -> some View {
        let content = HStack(spacing: 8) {
            Circle().fill(x.color).frame(width: 10, height: 10)
            Text(x.name).lineLimit(1)
            Spacer()
            Text(Money.eur(x.value)).monospacedDigit()
            Text("\(Int((x.value / total * 100).rounded()))%").foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .font(.subheadline)
        .contentShape(.rect)
        Button {
            if group == nil { withAnimation(.snappy) { group = x.name } } else { openCategory(x.name) }
        } label: { content }
        .buttonStyle(.plain)
    }
}
