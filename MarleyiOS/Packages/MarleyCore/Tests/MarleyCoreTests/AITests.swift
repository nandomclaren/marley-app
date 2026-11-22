import XCTest
@testable import MarleyCore

/// Scripted Messages API: returns queued responses as SSE lines and records every request body.
final class MockStreamer: AIStreamer, @unchecked Sendable {
    enum Reply { case blocks([JSONObject], stop: String), error(Int, String) }
    var queue: [Reply] = []
    var bodies: [JSONObject] = []
    func stream(body: Data, onEvent: @escaping @Sendable (AIStreamEvent) -> Void) async throws -> AIResponse {
        bodies.append(try JSON.parse(body).objectValue!)
        guard !queue.isEmpty else { throw AIError.api("no scripted reply", status: 500) }
        switch queue.removeFirst() {
        case .error(let s, let m): throw AIError.api(m, status: s)
        case .blocks(let blocks, let stop):
            var acc = SSEAccumulator()
            func ev(_ o: JSONObject) throws { if let e = try acc.feed(line: "data: " + JSON.serialize(.object(o))) { onEvent(e) } }
            try ev(JSONObject([("type", .string("message_start")), ("message", .object(JSONObject([("usage", .object(JSONObject([("input_tokens", .number(100)), ("cache_creation_input_tokens", .number(10000))])))])))]))
            for (i, b) in blocks.enumerated() {
                let idx = JSONValue.number(Double(i))
                switch b["type"]?.stringValue {
                case "text":
                    try ev(JSONObject([("type", .string("content_block_start")), ("index", idx), ("content_block", .object(JSONObject([("type", .string("text")), ("text", .string(""))])))]))
                    let t = b["text"]!.stringValue!, h = t.index(t.startIndex, offsetBy: t.count / 2)
                    for part in [String(t[..<h]), String(t[h...])] { try ev(JSONObject([("type", .string("content_block_delta")), ("index", idx), ("delta", .object(JSONObject([("type", .string("text_delta")), ("text", .string(part))])))])) }
                case "thinking":
                    try ev(JSONObject([("type", .string("content_block_start")), ("index", idx), ("content_block", .object(JSONObject([("type", .string("thinking")), ("thinking", .string("")), ("signature", .string(""))])))]))
                    try ev(JSONObject([("type", .string("content_block_delta")), ("index", idx), ("delta", .object(JSONObject([("type", .string("signature_delta")), ("signature", b["signature"]!)])))]))
                default: // tool_use
                    try ev(JSONObject([("type", .string("content_block_start")), ("index", idx), ("content_block", .object(JSONObject([("type", .string("tool_use")), ("id", b["id"]!), ("name", b["name"]!), ("input", .object(JSONObject()))])))]))
                    let j = JSON.serialize(b["input"]!), third = j.count / 3
                    let parts = [String(j.prefix(third)), String(j.dropFirst(third).prefix(third)), String(j.dropFirst(2 * third))]
                    for p in parts { try ev(JSONObject([("type", .string("content_block_delta")), ("index", idx), ("delta", .object(JSONObject([("type", .string("input_json_delta")), ("partial_json", .string(p))])))])) }
                }
                try ev(JSONObject([("type", .string("content_block_stop")), ("index", idx)]))
            }
            try ev(JSONObject([("type", .string("message_delta")), ("delta", .object(JSONObject([("stop_reason", .string(stop))]))), ("usage", .object(JSONObject([("output_tokens", .number(300))])))]))
            return try acc.finish()
        }
    }
}
func text(_ s: String) -> JSONObject { JSONObject([("type", .string("text")), ("text", .string(s))]) }
func thinking(_ sig: String) -> JSONObject { JSONObject([("type", .string("thinking")), ("signature", .string(sig))]) }
func tool(_ id: String, _ name: String, _ input: String) -> JSONObject { JSONObject([("type", .string("tool_use")), ("id", .string(id)), ("name", .string(name)), ("input", try! JSON.parse(input))]) }
func op(_ fields: String) -> String {
    let base = #"{"op":"add","id":null,"date":null,"desc":null,"acct":null,"type":null,"amount":null,"cat":null,"notes":null,"a_confirmar":null,"recurring":null,"month":null,"reason":"teste"}"#
    var o = try! JSON.parse(base).objectValue!
    for (k, v) in try! JSON.parse(fields).objectValue!.pairs { o[k] = v }
    return JSON.serialize(.object(o))
}

@MainActor
final class AIChatTests: XCTestCase {
    var data: AppData!
    var chat: AIChat!
    var api: MockStreamer!
    var saved: AIConversation?

    override func setUp() async throws {
        data = makeData([
            T(1, "2026-11-01", "Salário AKQA", in_: 5000, style: "salary"),
            T(2, "2026-11-02", "Monoprix", out: 80, cat: "🛒 Courses & Marché", locked: true),
            T(3, "2026-11-03", "Uber Eats", out: 25, cat: "🍕 Uber Eats & Restos"),
            T(40, "2026-06-10", "Amazon Prime Vidéo", out: 6.99, cat: "💻 Abonnements", locked: true),
            T(42, "2026-07-02", "AMAZON prime", acct: "Wise", out: 6.99, cat: "💻 Abonnements", locked: true),
        ], months: ["2026-11"], budgets: [("2026-11", [("🛒 Courses & Marché", 900)])])
        api = MockStreamer()
        chat = AIChat(streamer: api, getData: { [unowned self] in self.data }, mutateData: { [unowned self] f in f(&self.data) }, today: { "2026-11-22" })
        chat.persist = { [unowned self] c in self.saved = c }
    }

    func testQuestionRequestShapeAndContext() async throws {
        api.queue = [.blocks([thinking("SIG-1"), text("Você gastou **€ 105,00**.")], stop: "end_turn")]
        await chat.send("Quanto gastei?")
        let b = api.bodies[0]
        XCTAssertEqual(b["model"]?.stringValue, "claude-sonnet-5-5")
        XCTAssertEqual(b["output_config"]?.objectValue?["effort"]?.stringValue, "medium")
        XCTAssertNotNil(b["cache_control"]); XCTAssertNil(b["thinking"]); XCTAssertNil(b["tool_choice"]); XCTAssertNil(b["temperature"])
        XCTAssertEqual(b["tools"]?.arrayValue?.compactMap { $0.objectValue?["name"]?.stringValue }, ["search_transactions", "propose_changes"])
        let ctx = b["system"]!.arrayValue![1].objectValue!["text"]!.stringValue!
        XCTAssertTrue(ctx.contains("2|2026-11-02|Monoprix|Revolut|-80.00|🛒 Courses & Marché|L|"))
        XCTAssertFalse(ctx.contains("40|2026-06-10"))
        XCTAssertTrue(ctx.contains("2026-06: 1 transações · entradas 0.00 · saídas 6.99"))
        XCTAssertTrue(ctx.contains("A Alocar hoje: 4100.00"))
        XCTAssertNotNil(b["system"]!.arrayValue![1].objectValue!["cache_control"])
        XCTAssertEqual(chat.items.count, 2)
        if case .assistant(_, let t) = chat.items[1] { XCTAssertEqual(t, "Você gastou **€ 105,00**.") } else { XCTFail() }
        XCTAssertGreaterThan(chat.conversation!.cost, 0)
        XCTAssertNotNil(saved)
    }

    func testSearchRunsByItself() async throws {
        api.queue = [
            .blocks([tool("toolu_S", "search_transactions", #"{"date_from":"2026-06-01","date_to":"2026-07-31","text":"amazon","category":null,"account":null,"type":null,"limit":null}"#)], stop: "tool_use"),
            .blocks([text("Foram 2 compras.")], stop: "end_turn"),
        ]
        await chat.send("amazon no verão?")
        XCTAssertEqual(api.bodies.count, 2)
        let r = api.bodies[1]["messages"]!.arrayValue!.last!.objectValue!["content"]!.arrayValue![0].objectValue!
        XCTAssertEqual(r["tool_use_id"]?.stringValue, "toolu_S")
        XCTAssertTrue(r["content"]!.stringValue!.hasPrefix("2 transações encontradas. Soma: entradas 0.00, saídas 13.98."))
        XCTAssertTrue(chat.items.contains { if case .search(_, let l) = $0 { return l.contains("\"amazon\" (2)") }; return false })
    }

    func testProposalWaitsAppliesAndEchoesThinking() async throws {
        api.queue = [.blocks([thinking("SIG-2"), text("Proponho:"), tool("toolu_A", "propose_changes", #"{"summary":"Sofá e ajustes","operations":[\#(op(#"{"op":"add","date":"2026-11-20","desc":"Sofá 1/2","acct":"Wise","type":"saida","amount":50.01,"cat":"🛋️ Équipement Maison"}"#)),\#(op(#"{"op":"update","id":3,"amount":30}"#)),\#(op(#"{"op":"delete","id":1}"#)),\#(op(#"{"op":"set_budget","month":"2026-11","cat":"🛒 Courses & Marché","amount":1000}"#))]}"#)], stop: "tool_use")]
        await chat.send("lança o sofá")
        XCTAssertEqual(api.bodies.count, 1)
        XCTAssertEqual(data.txns.count, 5) // nothing applied yet
        guard case .proposal(let id, _, let ops, nil)? = chat.items.last else { return XCTFail() }
        XCTAssertEqual(ops.count, 4)
        api.queue = [.blocks([text("Feito!")], stop: "end_turn")]
        await chat.apply(id)
        let sofa = data.txns.first { $0.desc == "Sofá 1/2" }!
        XCTAssertEqual(sofa.out, 50.01); XCTAssertEqual(sofa.acct, "Wise"); XCTAssertFalse(sofa.locked)
        XCTAssertEqual(data.txn(3)?.out, 30); XCTAssertEqual(data.txn(3)?.desc, "Uber Eats")
        XCTAssertNil(data.txn(1))
        XCTAssertEqual(data.budget("2026-11", "🛒 Courses & Marché"), 1000)
        XCTAssertTrue(data.txn(2)!.locked)
        let msgs = api.bodies[1]["messages"]!.arrayValue!
        let res = msgs.last!.objectValue!["content"]!.arrayValue![0].objectValue!
        XCTAssertTrue(res["content"]!.stringValue!.contains("aplicou") && res["content"]!.stringValue!.contains(String(sofa.id)))
        let echoed = msgs[msgs.count - 2].objectValue!["content"]!.arrayValue!
        XCTAssertEqual(echoed[0].objectValue!["signature"]?.stringValue, "SIG-2")
        if case .proposal(_, _, _, let d)? = chat.items.first(where: { $0.id == id }) { XCTAssertEqual(d?.status, "applied") } else { XCTFail() }
    }

    func testRejectAndInvalidProposal() async throws {
        api.queue = [.blocks([tool("toolu_B", "propose_changes", #"{"summary":"Apagar","operations":[\#(op(#"{"op":"delete","id":3}"#))]}"#)], stop: "tool_use")]
        await chat.send("apaga o uber")
        api.queue = [.blocks([text("Ok.")], stop: "end_turn")]
        await chat.reject("toolu_B")
        XCTAssertNotNil(data.txn(3))
        XCTAssertTrue(api.bodies.last!["messages"]!.arrayValue!.last!.objectValue!["content"]!.arrayValue![0].objectValue!["content"]!.stringValue!.contains("recusou"))
        // invalid: touching a reconciled txn goes back to the model with is_error, never shown
        let n = api.bodies.count
        api.queue = [
            .blocks([tool("toolu_C", "propose_changes", #"{"summary":"Apagar Monoprix","operations":[\#(op(#"{"op":"delete","id":2}"#))]}"#)], stop: "tool_use"),
            .blocks([text("Está reconciliada.")], stop: "end_turn"),
        ]
        await chat.send("apaga o monoprix")
        let r = api.bodies[n + 1]["messages"]!.arrayValue!.last!.objectValue!["content"]!.arrayValue![0].objectValue!
        XCTAssertEqual(r["is_error"]?.boolValue, true)
        XCTAssertTrue(r["content"]!.stringValue!.contains("reconciliada"))
        XCTAssertFalse(chat.items.contains { $0.id == "toolu_C" })
        XCTAssertNotNil(data.txn(2))
    }

    func testOutsideChangesNoteOnceAndAppendOnlyHistory() async throws {
        api.queue = [.blocks([text("Oi.")], stop: "end_turn"), .blocks([text("Vi.")], stop: "end_turn"), .blocks([text("Ok.")], stop: "end_turn")]
        await chat.send("oi")
        data.txns.append(T(5555, "2026-11-22", "Padaria", out: 3.2, cat: "🥐 Boulangerie"))
        await chat.send("e agora?")
        let u = api.bodies[1]["messages"]!.arrayValue!.last!.objectValue!["content"]!.arrayValue!
        XCTAssertEqual(u.count, 2)
        XCTAssertTrue(u[0].objectValue!["text"]!.stringValue!.hasPrefix("<aviso_do_app>"))
        XCTAssertTrue(u[0].objectValue!["text"]!.stringValue!.contains("5555|2026-11-22|Padaria"))
        await chat.send("mais?")
        XCTAssertEqual(api.bodies[2]["messages"]!.arrayValue!.last!.objectValue!["content"]!.arrayValue!.count, 1)
        XCTAssertFalse(chat.items.contains { if case .user(_, let t) = $0 { return t.contains("aviso") }; return false })
        for k in 1..<api.bodies.count {
            let a = api.bodies[k - 1], b = api.bodies[k]
            XCTAssertEqual(a["system"], b["system"]); XCTAssertEqual(a["tools"], b["tools"])
            let am = a["messages"]!.arrayValue!, bm = b["messages"]!.arrayValue!
            XCTAssertEqual(Array(bm.prefix(am.count)), am)
        }
    }

    func testErrorRetryAndPersistence() async throws {
        api.queue = [.error(401, "invalid x-api-key")]
        await chat.send("oi")
        XCTAssertEqual(chat.lastError, "Chave da API inválida. Confira nas Configurações.")
        XCTAssertTrue(chat.canRetry)
        api.queue = [.blocks([text("Olá!")], stop: "end_turn")]
        await chat.retry()
        XCTAssertNil(chat.lastError)
        let last = api.bodies.last!["messages"]!.arrayValue!
        XCTAssertEqual(last.count, 1) // same user turn, not duplicated
        let restored = AIConversation.fromJSON(saved!.toJSON())
        XCTAssertEqual(restored, saved)
        chat.newChat()
        XCTAssertNil(chat.conversation)
    }
}
