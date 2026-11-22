import Foundation
import Observation

// MARK: - Streaming

public struct AIResponse: Sendable {
    public var content: [JSONValue]
    public var stopReason: String
    public var usage: JSONObject
}
public enum AIStreamEvent: Sendable { case text(String), thinking }

/// Accumulates the Messages API server-sent events into the assistant turn, exactly as received
/// (thinking blocks keep their signature, so they can be sent back unchanged).
public struct SSEAccumulator {
    var blocks: [Int: JSONObject] = [:]
    var toolJSON: [Int: String] = [:]
    var stopReason: String?
    var usage = JSONObject()
    public init() {}

    public mutating func feed(line: String) throws -> AIStreamEvent? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, case .object(let ev) = try JSON.parse(payload) else { return nil }
        switch ev["type"]?.stringValue {
        case "message_start":
            for (k, v) in ev["message"]?.objectValue?["usage"]?.objectValue?.pairs ?? [] { usage[k] = v }
        case "content_block_start":
            guard let i = ev["index"]?.intValue, let b = ev["content_block"]?.objectValue else { break }
            blocks[i] = b
            if b["type"]?.stringValue == "tool_use" { toolJSON[i] = "" }
            if ["thinking", "redacted_thinking"].contains(b["type"]?.stringValue ?? "") { return .thinking }
        case "content_block_delta":
            guard let i = ev["index"]?.intValue, var b = blocks[i], let d = ev["delta"]?.objectValue else { break }
            switch d["type"]?.stringValue {
            case "text_delta":
                let t = d["text"]?.stringValue ?? ""
                b["text"] = .string((b["text"]?.stringValue ?? "") + t); blocks[i] = b
                return .text(t)
            case "thinking_delta":
                b["thinking"] = .string((b["thinking"]?.stringValue ?? "") + (d["thinking"]?.stringValue ?? "")); blocks[i] = b
            case "signature_delta":
                b["signature"] = d["signature"] ?? .string(""); blocks[i] = b
            case "input_json_delta":
                toolJSON[i, default: ""] += d["partial_json"]?.stringValue ?? ""
            default: break
            }
        case "content_block_stop":
            guard let i = ev["index"]?.intValue, var b = blocks[i], b["type"]?.stringValue == "tool_use" else { break }
            let j = toolJSON[i] ?? ""
            b["input"] = j.isEmpty ? .object(JSONObject()) : try JSON.parse(j)
            blocks[i] = b
        case "message_delta":
            if let s = ev["delta"]?.objectValue?["stop_reason"]?.stringValue { stopReason = s }
            for (k, v) in ev["usage"]?.objectValue?.pairs ?? [] { usage[k] = v }
        case "error":
            throw AIError.api(ev["error"]?.objectValue?["message"]?.stringValue ?? "erro no streaming", status: nil)
        default: break
        }
        return nil
    }
    public func finish() throws -> AIResponse {
        guard let stopReason else { throw AIError.api("a resposta chegou incompleta", status: nil) }
        return AIResponse(content: blocks.keys.sorted().map { .object(blocks[$0]!) }, stopReason: stopReason, usage: usage)
    }
}

public enum AIError: Error, Equatable, LocalizedError {
    case api(String, status: Int?)
    case noKey
    public var errorDescription: String? {
        switch self {
        case .noKey: return "Sem chave da API."
        case .api(let m, let status):
            switch status {
            case 401: return "Chave da API inválida. Confira nas Configurações."
            case 429: return "Limite de uso da API atingido. Espere um pouco e tente de novo."
            case 503, 529: return "A API está sobrecarregada agora. Tente de novo em instantes."
            default: return m.lowercased().contains("credit balance") ? "Sem créditos na conta da Anthropic (console.anthropic.com → Billing)." : "Erro: \(m)"
            }
        }
    }
}

/// Sends one Messages API request and streams it back.
public protocol AIStreamer: Sendable {
    func stream(body: Data, onEvent: @escaping @Sendable (AIStreamEvent) -> Void) async throws -> AIResponse
}

// MARK: - Conversation

public struct AIDecision: Equatable, Sendable {
    public var status: String   // applied | rejected | invalid | auto | ignored
    public var result: String
    public var count: Int?
}

public struct AIConversation: Equatable, Sendable {
    public var system: [JSONValue]
    public var messages: [JSONValue] = []
    public var seen: AI.Seen
    public var decisions: [String: AIDecision] = [:]
    public var cost: Double = 0

    public init(data: AppData, today: String) {
        system = [
            .object(JSONObject([("type", .string("text")), ("text", .string(AIPrompt.instructions))])),
            .object(JSONObject([("type", .string("text")), ("text", .string("Dados do Marley no início desta conversa:\n\n" + AI.context(data, today: today))),
                                ("cache_control", .object(JSONObject([("type", .string("ephemeral"))])))])),
        ]
        seen = AI.seen(data, today: today)
    }

    public func requestBody() -> Data {
        let body = JSONObject([
            ("model", .string(AI.model)), ("max_tokens", .number(16000)), ("stream", .bool(true)),
            ("output_config", .object(JSONObject([("effort", .string("medium"))]))),
            ("cache_control", .object(JSONObject([("type", .string("ephemeral"))]))),
            ("system", .array(system)), ("tools", AIPrompt.tools), ("messages", .array(messages)),
        ])
        return Data(JSON.serialize(.object(body)).utf8)
    }

    var lastMessage: JSONObject? { messages.last?.objectValue }
    public var lastAssistantToolUses: [JSONObject] {
        guard let m = lastMessage, m["role"]?.stringValue == "assistant" else { return [] }
        return (m["content"]?.arrayValue ?? []).compactMap(\.objectValue).filter { $0["type"]?.stringValue == "tool_use" }
    }
    public var pendingToolUses: [JSONObject] { lastAssistantToolUses.filter { decisions[$0["id"]?.stringValue ?? ""] == nil } }
    public var endsWithUser: Bool { lastMessage?["role"]?.stringValue == "user" }

    /// Adds blocks to a new user turn, or to the last one if the previous request failed before any reply.
    mutating func pushUser(_ blocks: [JSONValue]) {
        if var last = lastMessage, last["role"]?.stringValue == "user" {
            last["content"] = .array((last["content"]?.arrayValue ?? []) + blocks)
            messages[messages.count - 1] = .object(last)
        } else {
            messages.append(.object(JSONObject([("role", .string("user")), ("content", .array(blocks))])))
        }
    }
    mutating func toolResultBlocks() -> [JSONValue] {
        lastAssistantToolUses.map { b in
            let id = b["id"]?.stringValue ?? ""
            if decisions[id] == nil { decisions[id] = AIDecision(status: "ignored", result: "O usuário não respondeu ao cartão e escreveu uma nova mensagem. Nada foi aplicado.") }
            let d = decisions[id]!
            var r = JSONObject([("type", .string("tool_result")), ("tool_use_id", .string(id)), ("content", .string(d.result))])
            if d.status == "invalid" { r["is_error"] = .bool(true) }
            return .object(r)
        }
    }
}

/// Text and cards to show, derived from the stored messages.
public enum AIChatItem: Identifiable, Sendable {
    case user(id: String, text: String)
    case assistant(id: String, text: String)
    case search(id: String, label: String)
    case proposal(id: String, summary: String, operations: [AI.Operation], decision: AIDecision?)
    public var id: String {
        switch self { case .user(let i, _), .assistant(let i, _), .search(let i, _), .proposal(let i, _, _, _): return i }
    }
}

// MARK: - Engine

/// The advisor loop: read-only searches run on their own, a valid proposal waits for the user's tap,
/// an invalid one goes straight back to the model. Data only changes through `apply`.
@MainActor @Observable
public final class AIChat {
    public private(set) var conversation: AIConversation?
    public private(set) var busy = false
    public private(set) var liveText = ""
    public private(set) var thinking = false
    public var lastError: String?

    @ObservationIgnored let streamer: AIStreamer
    @ObservationIgnored let getData: @MainActor () -> AppData
    @ObservationIgnored let mutateData: @MainActor ((inout AppData) -> Void) -> Void
    @ObservationIgnored let today: () -> String
    @ObservationIgnored public var persist: (AIConversation?) -> Void = { _ in }

    public init(streamer: AIStreamer, conversation: AIConversation? = nil,
                getData: @escaping @MainActor () -> AppData,
                mutateData: @escaping @MainActor ((inout AppData) -> Void) -> Void,
                today: @escaping () -> String = { Day.today() }) {
        self.streamer = streamer; self.conversation = conversation
        self.getData = getData; self.mutateData = mutateData; self.today = today
    }

    public var items: [AIChatItem] {
        guard let c = conversation else { return [] }
        var out: [AIChatItem] = []
        for (mi, m) in c.messages.enumerated() {
            guard let o = m.objectValue else { continue }
            let blocks = (o["content"]?.arrayValue ?? []).compactMap(\.objectValue)
            if o["role"]?.stringValue == "user" {
                let text = blocks.filter { $0["type"]?.stringValue == "text" }.compactMap { $0["text"]?.stringValue }
                    .filter { !$0.hasPrefix(AIPrompt.noteTag) }.joined(separator: "\n\n")
                if !text.isEmpty { out.append(.user(id: "u\(mi)", text: text)) }
            } else {
                for (bi, b) in blocks.enumerated() {
                    switch b["type"]?.stringValue {
                    case "text":
                        let t = b["text"]?.stringValue ?? ""
                        if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.append(.assistant(id: "a\(mi).\(bi)", text: t)) }
                    case "tool_use":
                        let id = b["id"]?.stringValue ?? "", input = b["input"]?.objectValue ?? JSONObject(), d = c.decisions[id]
                        if b["name"]?.stringValue == "search_transactions" { out.append(.search(id: id, label: AI.searchLabel(input, count: d?.count))) }
                        else if d?.status != "invalid" {
                            out.append(.proposal(id: id, summary: input["summary"]?.stringValue ?? "Proposta de alteração", operations: AI.operations(input), decision: d))
                        }
                    default: break
                    }
                }
            }
        }
        return out
    }
    public var canRetry: Bool { !busy && lastError != nil && (conversation?.endsWithUser ?? false) }

    public func newChat() { guard !busy else { return }; conversation = nil; lastError = nil; persist(nil) }

    public func send(_ text: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        if conversation == nil { conversation = AIConversation(data: getData(), today: today()) }
        var blocks = conversation!.toolResultBlocks()
        if let note = AI.changes(getData(), since: conversation!.seen, today: today()) {
            blocks.append(.object(JSONObject([("type", .string("text")), ("text", .string("\(AIPrompt.noteTag)\n\(note)\n</aviso_do_app>"))])))
            conversation!.seen = AI.seen(getData(), today: today())
        }
        blocks.append(.object(JSONObject([("type", .string("text")), ("text", .string(text))])))
        conversation!.pushUser(blocks)
        persist(conversation)
        await run()
    }

    public func retry() async { if canRetry { await run() } }

    public func apply(_ toolUseId: String) async {
        guard !busy, let c = conversation, let use = c.pendingToolUses.first(where: { $0["id"]?.stringValue == toolUseId }) else { return }
        let outside = AI.changes(getData(), since: c.seen, today: today())
        var result = ""
        let input = use["input"]?.objectValue ?? JSONObject()
        mutateData { d in result = AI.apply(&d, input) }
        if let outside { result += "\nAlém disso, os dados mudaram fora da conversa:\n" + outside }
        conversation!.decisions[toolUseId] = AIDecision(status: "applied", result: result)
        conversation!.seen = AI.seen(getData(), today: today())
        await afterDecision()
    }
    public func reject(_ toolUseId: String) async {
        guard !busy, conversation?.pendingToolUses.contains(where: { $0["id"]?.stringValue == toolUseId }) == true else { return }
        conversation!.decisions[toolUseId] = AIDecision(status: "rejected", result: "O usuário recusou a proposta. Nada foi aplicado.")
        await afterDecision()
    }
    func afterDecision() async {
        persist(conversation)
        guard conversation!.pendingToolUses.isEmpty else { return }
        conversation!.pushUser(conversation!.toolResultBlocks())
        persist(conversation)
        await run()
    }

    func run() async {
        busy = true; lastError = nil; liveText = ""; thinking = true
        defer { busy = false; liveText = ""; thinking = false; persist(conversation) }
        do {
            for _ in 0..<8 {
                try Task.checkCancellation()
                let body = conversation!.requestBody()
                let r = try await streamer.stream(body: body) { [weak self] ev in
                    Task { @MainActor in
                        guard let self else { return }
                        switch ev {
                        case .text(let t): self.thinking = false; self.liveText += t
                        case .thinking: self.thinking = true
                        }
                    }
                }
                conversation!.cost += AI.cost(r.usage)
                liveText = ""
                if r.stopReason == "refusal" { lastError = "A IA não quis responder a isto. Tente reformular."; return }
                conversation!.messages.append(.object(JSONObject([("role", .string("assistant")), ("content", .array(r.content))])))
                persist(conversation)
                if r.stopReason == "max_tokens" { lastError = "A resposta ficou grande demais e foi cortada."; return }
                guard r.stopReason == "tool_use" else { return }
                var anyInvalid = false
                for use in conversation!.lastAssistantToolUses {
                    let id = use["id"]?.stringValue ?? "", input = use["input"]?.objectValue ?? JSONObject()
                    switch use["name"]?.stringValue {
                    case "search_transactions":
                        let s = AI.search(getData(), input)
                        conversation!.decisions[id] = AIDecision(status: "auto", result: s.result, count: s.count)
                    case "propose_changes":
                        let errs = AI.validate(getData(), input)
                        if !errs.isEmpty {
                            anyInvalid = true
                            conversation!.decisions[id] = AIDecision(status: "invalid", result: "Proposta inválida, nada foi mostrado ao usuário. Corrija e proponha de novo:\n- " + errs.joined(separator: "\n- "))
                        }
                    default:
                        anyInvalid = true
                        conversation!.decisions[id] = AIDecision(status: "invalid", result: "ferramenta desconhecida: \(use["name"]?.stringValue ?? "")")
                    }
                }
                if anyInvalid {
                    for use in conversation!.pendingToolUses {
                        conversation!.decisions[use["id"]?.stringValue ?? ""] = AIDecision(status: "invalid", result: "Não mostrada ao usuário porque outra proposta da mesma resposta tinha erros. Proponha de novo.")
                    }
                }
                if !conversation!.pendingToolUses.isEmpty { return } // wait for the user's tap
                conversation!.pushUser(conversation!.toolResultBlocks())
                persist(conversation)
            }
        } catch is CancellationError {
            lastError = "Resposta interrompida."
        } catch let e as URLError where e.code == .cancelled {
            lastError = "Resposta interrompida."
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Persistence

extension AIConversation {
    public func toJSON() -> String {
        var seenT = JSONObject(); for (k, v) in seen.txns.sorted(by: { $0.key < $1.key }) { seenT[String(k)] = .number(Double(v)) }
        var seenB = JSONObject(); for (k, v) in seen.budgets.sorted(by: { $0.key < $1.key }) { seenB[k] = .number(Double(v)) }
        var dec = JSONObject()
        for (k, v) in decisions.sorted(by: { $0.key < $1.key }) {
            var o = JSONObject([("status", .string(v.status)), ("result", .string(v.result))])
            if let c = v.count { o["count"] = .number(Double(c)) }
            dec[k] = .object(o)
        }
        return JSON.serialize(.object(JSONObject([
            ("version", .number(2)), ("system", .array(system)), ("messages", .array(messages)),
            ("seen", .object(JSONObject([("txns", .object(seenT)), ("budgets", .object(seenB)), ("today", .string(seen.today))]))),
            ("decisions", .object(dec)), ("cost", .number(cost)),
        ])))
    }
    public static func fromJSON(_ s: String) -> AIConversation? {
        guard case .object(let o)? = try? JSON.parse(s), o["version"]?.intValue == 2,
              let system = o["system"]?.arrayValue, let messages = o["messages"]?.arrayValue, let seen = o["seen"]?.objectValue else { return nil }
        var t: [Int: Int32] = [:]; for (k, v) in seen["txns"]?.objectValue?.pairs ?? [] { if let i = Int(k), let n = v.intValue { t[i] = Int32(truncatingIfNeeded: n) } }
        var b: [String: Int32] = [:]; for (k, v) in seen["budgets"]?.objectValue?.pairs ?? [] { if let n = v.intValue { b[k] = Int32(truncatingIfNeeded: n) } }
        var c = AIConversation(system: system, seen: AI.Seen(txns: t, budgets: b, today: seen["today"]?.stringValue ?? ""))
        c.messages = messages
        for (k, v) in o["decisions"]?.objectValue?.pairs ?? [] {
            guard let d = v.objectValue else { continue }
            c.decisions[k] = AIDecision(status: d["status"]?.stringValue ?? "", result: d["result"]?.stringValue ?? "", count: d["count"]?.intValue)
        }
        c.cost = o["cost"]?.doubleValue ?? 0
        return c
    }
    init(system: [JSONValue], seen: AI.Seen) { self.system = system; self.seen = seen }
}
