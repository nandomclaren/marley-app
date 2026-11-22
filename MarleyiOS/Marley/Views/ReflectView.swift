import SwiftUI
import Charts
import MarleyCore

struct ReflectView: View {
    @Environment(AppStore.self) private var store
    @State private var path: [String] = []

    var body: some View {
        let d = store.data, today = store.today
        let m = store.selectedMonth == Ledger.startMonth ? (d.months.first { $0 != Ledger.startMonth } ?? store.selectedMonth) : store.selectedMonth
        let months = d.months.filter { $0 != Ledger.startMonth }
        let pastMonths = months.filter { $0 <= String(today.prefix(7)) }
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 16) {
                    card("Saldo de \(Day.monthLabel(m))", systemImage: "eurosign.circle.fill") {
                        let o = store.monthOverview(m)
                        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                            GridRow {
                                overviewStat("Início de \(Day.monthName(m).prefix(3).lowercased())", o.start)
                                overviewStat("Saldo hoje", o.today, note: Day.short(today))
                            }
                            GridRow {
                                overviewStat("Projetado fim do mês", o.projectedEnd)
                                if let minimum = o.minimum {
                                    overviewStat("⚠️ Mínimo do mês", minimum,
                                                 note: o.minimumDate.map { "em \(Day.short($0))" },
                                                 tint: minimum < Ledger.MonthOverview.lowThreshold ? .moneyOut : .marleyAccent)
                                } else {
                                    overviewStat("⚠️ Mínimo do mês", nil)
                                }
                            }
                        }
                    }
                    SpendingBreakdownCard(month: m) { cat in path.append(cat) }
                    card("Entradas vs saídas", systemImage: "chart.bar.fill") {
                        let flows = months.map { mo in Flow(month: mo, income: income(d, mo, today), expense: expense(d, mo, today)) }
                        Chart {
                            ForEach(flows) { f in
                                BarMark(x: .value("Mês", short(f.month)), y: .value("€", f.income)).foregroundStyle(by: .value("Tipo", "Entradas")).position(by: .value("Tipo", "Entradas"))
                                BarMark(x: .value("Mês", short(f.month)), y: .value("€", f.expense)).foregroundStyle(by: .value("Tipo", "Saídas")).position(by: .value("Tipo", "Saídas"))
                            }
                        }
                        .chartForegroundStyleScale(["Entradas": Color.moneyIn, "Saídas": Color.moneyOut])
                        .frame(height: 200)
                    }
                    card("Patrimônio", systemImage: "building.columns.fill") {
                        let b = store.balancesToday
                        Text(Money.eur(b.values.reduce(0, +))).font(.system(size: 32, weight: .bold).monospacedDigit())
                        HStack { ForEach(Accounts.all, id: \.self) { a in VStack(alignment: .leading) { Text(a).font(.caption).foregroundStyle(.secondary); Text(Money.eur(b[a] ?? 0)).font(.subheadline.monospacedDigit()) }.frame(maxWidth: .infinity, alignment: .leading) } }
                        let nw = pastMonths.map { mo in Point(month: mo, value: Ledger.balances(d, asOf: min(today, mo + "-31")).values.reduce(0, +)) }
                        Chart(nw) { p in
                            LineMark(x: .value("Mês", short(p.month)), y: .value("€", p.value)).interpolationMethod(.catmullRom)
                            PointMark(x: .value("Mês", short(p.month)), y: .value("€", p.value))
                        }
                        .frame(height: 160)
                    }
                    card("Idade do dinheiro", systemImage: "hourglass") {
                        if let aom = Ledger.ageOfMoney(d, asOf: today) {
                            Text("\(aom) dias").font(.system(size: 32, weight: .bold).monospacedDigit())
                            Text("Quanto tempo, em média, o dinheiro fica com você antes de ser gasto.").font(.caption).foregroundStyle(.secondary)
                        } else { Text("--").font(.title) }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Reflect")
            // subcategoria tocada no card de gastos → mesma tela de detalhe do Budget; "voltar" volta ao Reflect
            .navigationDestination(for: String.self) { CategoryDetailView(cat: $0) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { MonthMenu(hideFebruary: true) }
                ToolbarItem(placement: .topBarLeading) { SyncButton() }
            }
        }
    }

    func card<C: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage).font(.subheadline.weight(.semibold)).foregroundStyle(Color.marleyAccent)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background, in: .rect(cornerRadius: 20))
    }
    func short(_ m: String) -> String { String(Day.monthName(m).prefix(3)) }

    /// Um dos 4 cards do topo do Fluxo no web.
    func overviewStat(_ title: String, _ value: Double?, note: String? = nil, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(value.map { Money.eur($0) } ?? "—")
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint ?? ((value ?? 0) < -0.004 ? Color.moneyOut : .primary))
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(note ?? " ").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    /// Categorized spending up to today, by group (future-dated spending excluded, like the web Reflect).
    struct Flow: Identifiable { let month: String; let income: Double; let expense: Double; var id: String { month } }
    struct Point: Identifiable { let month: String; let value: Double; var id: String { month } }

    /// Entradas/saídas do mês inteiro, incluindo as agendadas (como os cards do Fluxo e o Reflect do web).
    func income(_ d: AppData, _ m: String, _ today: String) -> Double { d.txns.filter { $0.month == m && $0.in_ > 0 && $0.style != "opening" && $0.acct != "—" }.reduce(0) { $0 + $1.in_ } }
    func expense(_ d: AppData, _ m: String, _ today: String) -> Double { d.txns.filter { $0.month == m && $0.out > 0 && $0.style != "opening" }.reduce(0) { $0 + $1.out } }
}
