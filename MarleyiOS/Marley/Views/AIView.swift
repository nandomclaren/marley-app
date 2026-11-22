import SwiftUI
import MarleyCore

struct AIView: View {
    @Environment(AppStore.self) private var store
    @State private var input = ""
    @State private var task: Task<Void, Never>?
    @FocusState private var focused: Bool

    var chat: AIChat { store.ai }

    var body: some View {
        NavigationStack {
            Group {
                if !store.hasAIKey {
                    ContentUnavailableView {
                        Label("Consultor Marley", systemImage: "bubble.left.and.text.bubble.right")
                    } description: {
                        Text("Adicione a sua chave da API Anthropic nas configurações para conversar sobre as suas finanças.")
                    } actions: {
                        Button("Abrir configurações") { store.showSettings = true }.buttonStyle(.glassProminent)
                    }
                } else {
                    messages
                }
            }
            .navigationTitle("Consultor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let c = chat.conversation, c.cost > 0 { Text("≈ US$ \(String(format: "%.2f", c.cost))").font(.caption).foregroundStyle(.secondary) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { chat.newChat() } label: { Image(systemName: "square.and.pencil") }
                        .disabled(chat.busy || chat.conversation == nil).accessibilityLabel("Nova conversa")
                }
            }
        }
    }

    var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if chat.items.isEmpty { welcome }
                    ForEach(chat.items) { item in itemView(item).id(item.id) }
                    if chat.busy {
                        if !chat.liveText.isEmpty { bubble(MarkdownText(text: chat.liveText), mine: false) }
                        if chat.thinking || chat.liveText.isEmpty {
                            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Pensando…").foregroundStyle(.secondary) }.font(.subheadline)
                        }
                    }
                    if let e = chat.lastError {
                        VStack(spacing: 8) {
                            Text(e).font(.subheadline).foregroundStyle(Color.moneyOut).multilineTextAlignment(.center)
                            if chat.canRetry { Button("Tentar de novo") { run { await chat.retry() } }.buttonStyle(.glass) }
                        }.frame(maxWidth: .infinity)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.items.count) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
            .onChange(of: chat.liveText) { _, _ in proxy.scrollTo("bottom") }
            .safeAreaInset(edge: .bottom) { inputBar }
        }
    }

    var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            bubble(Text("Olá! Conheço os seus saldos, orçamentos e lançamentos. Pergunte o que quiser, ou peça para eu lançar ou ajustar algo. Antes de mudar qualquer coisa eu mostro um cartão, e você confirma."), mine: false)
            ForEach(["Como foi o meu mês até agora?", "Quanto ainda posso gastar até o fim do mês?", "Onde estou gastando mais do que o orçado?", "Como está o próximo mês com o que já está previsto?"], id: \.self) { q in
                Button(q) { send(q) }.buttonStyle(.glass).font(.subheadline)
            }
        }
    }

    @ViewBuilder func itemView(_ item: AIChatItem) -> some View {
        switch item {
        case .user(_, let text): bubble(Text(text), mine: true)
        case .assistant(_, let text): bubble(MarkdownText(text: text), mine: false)
        case .search(_, let label): Text(label).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        case .proposal(let id, let summary, let ops, let decision): ProposalCard(id: id, summary: summary, ops: ops, decision: decision, chat: chat, run: run)
        }
    }

    func bubble<V: View>(_ content: V, mine: Bool) -> some View {
        HStack {
            if mine { Spacer(minLength: 40) }
            content
                .textSelection(.enabled)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(mine ? Color.white : Color.primary)
                .background(mine ? AnyShapeStyle(Color.marleyAccent) : AnyShapeStyle(.background.secondary), in: .rect(cornerRadius: 18))
            if !mine { Spacer(minLength: 40) }
        }
    }

    var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Pergunte sobre as suas finanças…", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 14).padding(.vertical, 10)
            Button {
                if chat.busy { task?.cancel() } else { send(input) }
            } label: {
                Image(systemName: chat.busy ? "stop.fill" : "arrow.up").font(.headline).frame(width: 36, height: 36)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .disabled(!chat.busy && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(4)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .padding(.horizontal).padding(.bottom, 8)
        .disabled(!store.hasAIKey)
    }

    func send(_ text: String) {
        let t = text
        input = ""
        run { await chat.send(t) }
    }
    func run(_ work: @escaping @MainActor () async -> Void) {
        task = Task { await work() }
    }
}

struct ProposalCard: View {
    @Environment(AppStore.self) private var store
    let id: String
    let summary: String
    let ops: [AI.Operation]
    let decision: AIDecision?
    let chat: AIChat
    let run: (@escaping @MainActor () async -> Void) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(summary, systemImage: "square.and.pencil").font(.subheadline.weight(.semibold))
                .foregroundStyle(decision == nil ? Color.marleyAccent : .secondary)
            ForEach(Array(ops.enumerated()), id: \.offset) { _, op in
                VStack(alignment: .leading, spacing: 2) {
                    Text(describe(op)).font(.subheadline)
                    if !op.reason.isEmpty { Text(op.reason).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.vertical, 2)
            }
            if let d = decision {
                Text(d.status == "applied" ? "✅ Aplicado" : d.status == "rejected" ? "✖️ Recusado" : "— Sem resposta, nada aplicado")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            } else {
                HStack {
                    Spacer()
                    Button("Recusar") { run { await chat.reject(id) } }.buttonStyle(.glass)
                    Button("Aplicar") { run { await chat.apply(id) } }.buttonStyle(.glassProminent)
                }
                .disabled(chat.busy)
            }
        }
        .padding(14)
        .background(.background.secondary, in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(decision == nil ? Color.marleyAccent : .clear, lineWidth: 1.5))
    }

    func describe(_ op: AI.Operation) -> String {
        let val = { (type: String?, amount: Double) in (type == "entrada" ? "+" : "−") + Money.eur(amount) }
        switch op.op {
        case "add":
            return "➕ \(Day.short(op.date ?? "")) · \(op.desc ?? "") · \(val(op.type, op.amount ?? 0)) · \(op.acct ?? "")" + ((op.cat ?? "").isEmpty ? "" : " · \(op.cat!)") + (op.aConfirmar == true ? " · ⚠️" : "") + (op.recurring == true ? " · 🔁" : "")
        case "set_budget":
            let old = store.data.budget(op.month ?? "", op.cat ?? "")
            return "📊 Orçado \(Day.monthLabel(op.month ?? "")) · \(op.cat ?? ""): \(decision == nil ? Money.eur(old) + " → " : "")\(Money.eur(op.amount ?? 0))"
        case "delete":
            return "🗑 Apagar: " + label(op.id)
        default:
            let t = op.id.flatMap { store.data.txn($0) }
            var ch: [String] = []
            if let x = op.date { ch.append("data \(Day.short(x))") }
            if let x = op.desc { ch.append("descrição \"\(x)\"") }
            if let x = op.acct { ch.append("conta \(x)") }
            if op.type != nil || op.amount != nil { ch.append("valor " + val(op.type ?? (t?.isIncome == true ? "entrada" : "saida"), op.amount ?? t?.amount ?? 0)) }
            if let x = op.cat { ch.append("categoria \(x.isEmpty ? "(nenhuma)" : x)") }
            if let x = op.notes { ch.append("notas \"\(x)\"") }
            if let x = op.aConfirmar { ch.append(x ? "a confirmar" : "confirmada") }
            if let x = op.recurring { ch.append(x ? "recorrente" : "pontual") }
            return "✏️ \(label(op.id))\n→ \(ch.isEmpty ? "sem alterações" : ch.joined(separator: " · "))"
        }
    }
    func label(_ id: Int?) -> String {
        guard let id, let t = store.data.txn(id) else { return "#\(id.map(String.init) ?? "?")" }
        return "\(Day.short(t.date)) · \(displayDescription(t.desc)) · \(Money.eur(t.net, signed: true)) · \(t.acct)"
    }
}
