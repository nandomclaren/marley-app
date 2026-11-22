import XCTest
@testable import MarleyCore

func T(_ id: Int, _ date: String, _ desc: String, acct: String = "Revolut", out: Double = 0, in_: Double = 0,
       cat: String = "", style: String = "normal", recurring: Bool = false, cleared: Bool = false, locked: Bool = false) -> Txn {
    Txn(id: id, date: date, desc: desc, acct: acct, out: out, in_: in_, cat: cat, style: style, recurring: recurring, cleared: cleared, locked: locked)
}
func makeData(_ txns: [Txn], months: [String] = ["2026-10", "2026-11"], ts: Double = 1000,
              budgets: [(String, [(String, Double)])] = []) -> AppData {
    var rest = JSONObject([
        ("_lastModified", .number(ts)),
        ("months", .array(months.map { .string($0) })),
        ("balances", .object(JSONObject([("rev", .number(1000)), ("wise", .number(200)), ("swile", .number(50))]))),
        ("txns", .array([])),
        ("budgets", .object(JSONObject(budgets.map { ($0.0, .object(JSONObject($0.1.map { ($0.0, .number($0.1)) }))) }))),
        ("goals", .object(JSONObject())),
    ])
    rest["txns"] = .array([])
    return AppData(rest: rest, txns: txns)
}

final class JSONTests: XCTestCase {
    func testRoundTripIsExact() throws {
        // What JSON.stringify produces in the web app, including unicode, escapes and awkward numbers.
        let src = #"{"_lastModified":1795198573872,"txns":[{"id":9001,"desc":"🔧 Ajuste \"carry\"\nFeb→Mar","out":16.7,"in_":0.30000000000000004,"x":-0.5,"tiny":1e-7,"big":1e+21,"cat":"","locked":true,"n":null}],"months":["2026-02"],"z":{"b":1,"a":[1,2,{"c":"é"}]}}"#
        let v = try JSON.parse(src)
        XCTAssertEqual(JSON.serialize(v), src)
        if case .object(let o) = v { XCTAssertEqual(o.keys, ["_lastModified", "txns", "months", "z"]) } else { XCTFail() }
    }
    func testParsesWhitespaceAndUnicodeEscapes() throws {
        let v = try JSON.parse(" { \"a\" : [ 1 , 2.5 ] , \"s\" : \"\\u00e9\\ud83d\\ude00\\/\" } ")
        XCTAssertEqual(JSON.serialize(v), #"{"a":[1,2.5],"s":"é😀/"}"#)
    }
    func testRejectsGarbage() {
        XCTAssertThrowsError(try JSON.parse("<html>"))
        XCTAssertThrowsError(try JSON.parse("{\"a\":1,}"))
        XCTAssertThrowsError(try JSON.parse("{\"a\":1} x"))
    }
    func testAppDataKeepsUnknownFieldsAndOrder() throws {
        let src = #"{"_lastModified":5,"months":["2026-11"],"txns":[{"id":1,"date":"2026-11-02","desc":"A","acct":"Wise","out":3.2,"in_":0,"settledAt":123,"futureField":{"k":[1]}}],"budgets":{},"goals":{},"skipRecurring":{"2026-11":["X"]}}"#
        var d = try AppData.parse(src)
        XCTAssertEqual(d.serialized(), src)
        d.update(1) { $0.out = 4 }
        XCTAssertEqual(d.serialized(), src.replacingOccurrences(of: "\"out\":3.2", with: "\"out\":4"))
        XCTAssertEqual(d.skipRecurring("2026-11"), ["X"])
    }
}

final class LedgerTests: XCTestCase {
    func testBalancesAndAccountSummary() {
        let d = makeData([
            T(1, "2026-11-01", "Salário", in_: 5000, style: "salary"),
            T(2, "2026-11-02", "Monoprix", out: 80, cat: "🛒 Courses & Marché", locked: true),
            T(3, "2026-11-03", "Uber Eats", out: 25, cat: "🍕 Uber Eats & Restos", cleared: true),
            T(4, "2026-11-30", "Futuro", out: 999),
            T(5, "2026-11-04", "Swile", acct: "Swile", out: 10),
        ])
        let b = Ledger.balances(d, asOf: "2026-11-22")
        XCTAssertEqual(b["Revolut"]!, 1000 + 5000 - 80 - 25, accuracy: 0.001)
        XCTAssertEqual(b["Swile"]!, 40, accuracy: 0.001)
        let s = Ledger.accountSummary(d, "Revolut", today: "2026-11-22")
        XCTAssertEqual(s.cleared, 1000 - 80 - 25, accuracy: 0.001)
        XCTAssertEqual(s.uncleared, 5000, accuracy: 0.001)
        XCTAssertEqual(s.working, 5895, accuracy: 0.001)
        XCTAssertEqual(Ledger.running(d).last!.total, 1250 + 5000 - 80 - 25 - 999 - 10, accuracy: 0.001)
        XCTAssertEqual(Ledger.accountRows(d, "Revolut", month: "2026-11").map(\.total).last!, 5895 - 999, accuracy: 0.001)
    }
    func testMonthOverviewMatchesWebCards() {
        // abertura 1250; outubro termina em 1250 − 100 = 1150
        let d = makeData([
            T(1, "2026-10-10", "Out", out: 100),
            T(2, "2026-11-01", "Aluguel", out: 900),
            T(3, "2026-11-05", "Salário", in_: 3000),
            T(4, "2026-11-25", "Futuro", out: 200),
            T(5, "2026-11-03", "Mercado", out: 120),
        ])
        let o = Ledger.monthOverview(d, month: "2026-11", today: "2026-11-22")
        XCTAssertEqual(o.start, 1150, accuracy: 0.001)
        XCTAssertEqual(o.today, 1150 - 900 - 120 + 3000, accuracy: 0.001)
        XCTAssertEqual(o.projectedEnd, 1150 - 900 - 120 + 3000 - 200, accuracy: 0.001)
        XCTAssertEqual(o.minimum!, 1150 - 900 - 120, accuracy: 0.001)
        XCTAssertEqual(o.minimumDate, "2026-11-03")
        // mês sem transações: tudo igual ao início, sem mínimo
        let e = Ledger.monthOverview(d, month: "2026-12", today: "2026-11-22")
        XCTAssertEqual(e.start, e.projectedEnd); XCTAssertNil(e.minimum)
    }

    func testAAlocarOnlyUncategorizedMinusAllBudgets() {
        let d = makeData([
            T(1, "2026-03-01", "Salário", in_: 3000),
            T(2, "2026-02-10", "Antigo", in_: 500),
            T(3, "2026-03-02", "Saldo Inicial", in_: 1000, style: "opening"),
            T(4, "2026-03-05", "Categorizado", out: 200, cat: "🛒 Courses & Marché"),
            T(5, "2026-03-06", "Saque", out: 100),
            T(6, "2026-03-20", "Futuro", in_: 700),
        ], budgets: [("2026-03", [("🛒 Courses & Marché", 400), ("💸 Bail", 2800)]), ("2026-02", [("x", 999)])])
        XCTAssertEqual(Ledger.aAlocar(d, today: "2026-03-10"), 3000 - 100 - 3200, accuracy: 0.001)
    }
    func testBudgetCarryWalksForwardFromMarch() {
        let c = "🛒 Courses & Marché"
        let d = makeData([T(1, "2026-03-05", "M", out: 300, cat: c), T(2, "2026-04-05", "M", out: 500, cat: c), T(3, "2026-05-05", "M", out: 50, cat: c)],
                         budgets: [("2026-02", [(c, 999)]), ("2026-03", [(c, 400)]), ("2026-04", [(c, 400)]), ("2026-05", [(c, 100)])])
        XCTAssertEqual(Ledger.budgetCarry(d, month: "2026-03")[c] ?? 0, 0)
        XCTAssertEqual(Ledger.budgetCarry(d, month: "2026-04")[c]!, 100, accuracy: 0.001)
        XCTAssertEqual(Ledger.budgetCarry(d, month: "2026-05")[c]!, 0, accuracy: 0.001)
        let line = Ledger.categoryLines(d, month: "2026-05").first { $0.cat == c }!
        XCTAssertEqual(line.available, 50, accuracy: 0.001)
    }
    func testMoveMoney() {
        var d = makeData([], budgets: [("2026-11", [("🍕 Uber Eats & Restos", 100)])])
        Ledger.moveMoney(&d, month: "2026-11", from: "🍕 Uber Eats & Restos", to: "🛒 Courses & Marché", amount: 30)
        XCTAssertEqual(d.budget("2026-11", "🍕 Uber Eats & Restos"), 70)
        XCTAssertEqual(d.budget("2026-11", "🛒 Courses & Marché"), 30)
    }
    func testEnsureMonthsAheadAddsMonthsBudgetsAndRecurringOnce() {
        var d = makeData([T(1, "2026-11-01", "🏠 Bail", out: 2800, style: "fixed"), T(2, "2026-11-05", "Pão", out: 2)],
                         months: ["2026-10", "2026-11"], budgets: [("2026-11", [("💸 Bail", 2800)])])
        let added = Ledger.ensureMonthsAhead(&d, today: "2026-11-22")
        XCTAssertEqual(added, ["2026-12", "2027-01"])
        XCTAssertEqual(d.months, ["2026-10", "2026-11", "2026-12", "2027-01"])
        XCTAssertTrue(d.budgets(for: "2026-12").isEmpty && d.hasBudget(for: "2027-01"))
        XCTAssertEqual(d.txns.filter { $0.desc == "🏠 Bail" }.map(\.date), ["2026-11-01", "2026-12-01", "2027-01-01"])
        XCTAssertEqual(d.txns.filter { $0.desc == "Pão" }.count, 1)
        XCTAssertEqual(Ledger.ensureMonthsAhead(&d, today: "2026-11-22"), [])
        XCTAssertEqual(d.txns.count, 4)
    }
    func testRecurringRespectsSkipAndClampsDay() {
        var d = makeData([T(1, "2026-01-31", "📱 Assinatura", out: 10, style: "fixed")], months: ["2026-01", "2026-02"])
        XCTAssertEqual(Ledger.generateRecurring(&d, month: "2026-02"), 1)
        XCTAssertEqual(d.txns.last!.date, "2026-02-28")
        var d2 = makeData([T(1, "2026-10-01", "🏠 Bail", out: 2800, style: "fixed")])
        Ledger.delete(&d2, ids: [])
        d2.addSkipRecurring("2026-11", "🏠 Bail")
        XCTAssertEqual(Ledger.generateRecurring(&d2, month: "2026-11"), 0)
    }
    func testDeletingRecurringRecordsSkip() {
        var d = makeData([T(7, "2026-11-01", "💡 Électricité", out: 180, style: "fixed")])
        Ledger.delete(&d, ids: [7])
        XCTAssertTrue(d.txns.isEmpty)
        XCTAssertEqual(d.skipRecurring("2026-11"), ["💡 Électricité"])
    }
    func testResetFutureLocks() {
        var d = makeData([T(1, "2026-12-01", "F", locked: true), T(2, "2026-11-01", "P", locked: true)])
        Ledger.resetFutureLocks(&d, today: "2026-11-22")
        XCTAssertEqual(d.txns.map(\.locked), [false, true])
    }
    func testReconcileWithCorrection() {
        var d = makeData([T(1, "2026-11-02", "A", out: 100, cleared: true), T(2, "2026-11-03", "B", out: 50)])
        let corr = Ledger.reconcileWithCorrection(&d, "Revolut", bankBalance: 895.5, today: "2026-11-22")!
        XCTAssertTrue(d.txn(1)!.locked && !d.txn(1)!.cleared)
        XCTAssertFalse(d.txn(2)!.locked)
        XCTAssertEqual(corr.in_, 0); XCTAssertEqual(corr.out, 4.5, accuracy: 0.0001)
        XCTAssertTrue(corr.locked)
        XCTAssertEqual(Ledger.clearedBalance(d, "Revolut", today: "2026-11-22"), 895.5, accuracy: 0.001)
    }
    func testAgeOfMoneyFIFO() {
        let d = makeData([T(1, "2026-03-01", "Sal", in_: 1000), T(2, "2026-03-10", "Gasto", out: 1500)])
        // opening 1250 consumed first (dated at the first txn), then 250 of the March 1st income
        XCTAssertEqual(Ledger.ageOfMoney(d, asOf: "2026-03-21"), 20)
    }
}

final class InstallmentTests: XCTestCase {
    func testPlanSplitsWithRemainderOnFirstAndClampsDays() {
        let p = Installments.plan(total: 100, count: 6, date: "2026-11-30")
        XCTAssertEqual(p.map(\.amount), [16.7, 16.66, 16.66, 16.66, 16.66, 16.66])
        XCTAssertEqual(p.map(\.date), ["2026-11-30", "2026-12-30", "2027-01-30", "2027-02-28", "2027-03-30", "2027-04-30"])
        XCTAssertEqual(Int((p.reduce(0) { $0 + $1.amount } * 100).rounded()), 10000)
    }
    func testParse() {
        XCTAssertEqual(Installments.parse("Sofá 2/6"), .init(base: "Sofá", i: 2, n: 6))
        XCTAssertNil(Installments.parse("Sofá 7/6"))
        XCTAssertNil(Installments.parse("Sofá"))
        XCTAssertNil(Installments.parse("1/1"))
    }
    func testAddAndFollowing() {
        var d = makeData([])
        let ids = Installments.add(&d, total: 90, count: 3, date: "2026-11-10", desc: "Curso", acct: "Wise", isIncome: false, cat: "", notes: "", uncertain: false)
        XCTAssertEqual(d.txns.map(\.desc), ["Curso 1/3", "Curso 2/3", "Curso 3/3"])
        XCTAssertTrue(d.txns.allSatisfy { !$0.recurring && $0.out == 30 })
        XCTAssertEqual(Installments.following(d, d.txn(ids[0])!).map(\.id), [ids[1], ids[2]])
        XCTAssertEqual(Installments.following(d, d.txn(ids[2])!), [])
        // another purchase with the same name in other months is not mixed in
        _ = Installments.add(&d, total: 30, count: 3, date: "2027-03-10", desc: "Curso", acct: "Wise", isIncome: false, cat: "", notes: "", uncertain: false)
        XCTAssertEqual(Installments.following(d, d.txn(ids[0])!).count, 2)
    }
}

// MARK: - Sync

final class MockGist: GistTransport, @unchecked Sendable {
    var content: String?
    var pushes: [String] = []
    var failFetch = false
    init(_ d: AppData?) { content = d?.serialized() }
    func fetch() async throws -> String? { if failFetch { throw SyncError.badResponse }; return content }
    func push(_ c: String) async throws { pushes.append(c); content = c }
}

final class SyncTests: XCTestCase {
    func data(n: Int, locked: Int = 0, ts: Double) -> AppData {
        makeData((1...n).map { T($0, "2026-11-01", "T\($0)", out: 10, locked: $0 <= locked) }, ts: ts)
    }
    func testLocalNewerPushes() async throws {
        let g = MockGist(data(n: 19, ts: 1000)); var st = SyncState(lastSyncedTs: 1000)
        let r = try await Sync.full(local: data(n: 20, ts: 2000), state: &st, transport: g) { _ in XCTFail("no question expected"); return false }
        XCTAssertEqual(r.outcome, .pushed); XCTAssertEqual(g.pushes.count, 1); XCTAssertEqual(st.lastSyncedTs, 2000); XCTAssertTrue(st.hasSyncedThisSession)
    }
    func testRemoteNewerIsAdopted() async throws {
        let g = MockGist(data(n: 25, ts: 3000)); var st = SyncState(lastSyncedTs: 1000)
        let r = try await Sync.full(local: data(n: 20, ts: 1000), state: &st, transport: g) { _ in XCTFail(); return false }
        XCTAssertEqual(r.outcome, .pulled); XCTAssertEqual(r.data?.txns.count, 25); XCTAssertTrue(g.pushes.isEmpty); XCTAssertEqual(st.lastSyncedTs, 3000)
    }
    func testEqualTimestampsDoNothing() async throws {
        let g = MockGist(data(n: 5, ts: 1000)); var st = SyncState(lastSyncedTs: 500)
        let r = try await Sync.full(local: data(n: 5, ts: 1000), state: &st, transport: g) { _ in false }
        XCTAssertEqual(r.outcome, .upToDate); XCTAssertTrue(g.pushes.isEmpty); XCTAssertTrue(st.hasSyncedThisSession)
    }
    func testBothChangedAsksAndKeepLocalWinsWithNewerStamp() async throws {
        let g = MockGist(data(n: 22, ts: 3000)); var st = SyncState(lastSyncedTs: 1000)
        var asked: [SyncQuestion] = []
        let r = try await Sync.full(local: data(n: 21, ts: 2000), state: &st, transport: g, now: 5000) { q in asked.append(q); return true }
        XCTAssertEqual(asked, [.conflict(localTs: 2000, remoteTs: 3000)])
        XCTAssertEqual(r.outcome, .pushed); XCTAssertEqual(r.data?.lastModified, 5000)
        XCTAssertEqual(try AppData.parse(g.content!).lastModified, 5000); XCTAssertEqual(st.lastSyncedTs, 5000)
    }
    func testBothChangedAdoptRemote() async throws {
        let g = MockGist(data(n: 22, ts: 3000)); var st = SyncState(lastSyncedTs: 1000)
        let r = try await Sync.full(local: data(n: 21, ts: 4000), state: &st, transport: g) { _ in false }
        XCTAssertEqual(r.outcome, .pulled); XCTAssertEqual(r.data?.txns.count, 22); XCTAssertTrue(g.pushes.isEmpty)
    }
    func testAdoptingServerWithFewerReconciledAsks() async throws {
        let g = MockGist(data(n: 30, locked: 2, ts: 3000)); var st = SyncState(lastSyncedTs: 1000)
        let r = try await Sync.full(local: data(n: 25, locked: 20, ts: 1000), state: &st, transport: g) { q in
            XCTAssertEqual(q, .remoteHasFewerReconciled(local: 20, remote: 2)); return false }
        XCTAssertEqual(r.outcome, .cancelled); XCTAssertNil(r.data); XCTAssertFalse(st.hasSyncedThisSession)
    }
    func testPushThatLooksLikeDataLossAsks() async throws {
        let g = MockGist(data(n: 20, ts: 1000)); var st = SyncState(lastSyncedTs: 1000)
        let r = try await Sync.full(local: data(n: 10, ts: 2000), state: &st, transport: g) { q in
            if case .pushLooksLikeDataLoss(let issues) = q { XCTAssertTrue(issues[0].contains("10 transações a menos")) } else { XCTFail() }
            return false }
        if case .blocked(let issues) = r.outcome { XCTAssertEqual(issues.first, "10 transações a menos que o servidor (10 vs 20)"); XCTAssertEqual(issues.count, 2) } else { XCTFail() }
        XCTAssertTrue(g.pushes.isEmpty)
    }
    func testInvalidRemotePushesLocal() async throws {
        let g = MockGist(nil); g.content = "<html>"; var st = SyncState(lastSyncedTs: 0)
        let r = try await Sync.full(local: data(n: 3, ts: 10), state: &st, transport: g) { _ in false }
        XCTAssertEqual(r.outcome, .pushed)
    }
    func testAutoPushRules() async {
        let g = MockGist(data(n: 20, ts: 1000))
        var st = SyncState(lastSyncedTs: 1000)
        // not synced yet this session -> never pushes
        var o = await Sync.autoPush(local: data(n: 21, ts: 2000), state: &st, transport: g)
        XCTAssertEqual(o, .upToDate); XCTAssertTrue(g.pushes.isEmpty)
        st.hasSyncedThisSession = true
        o = await Sync.autoPush(local: data(n: 21, ts: 2000), state: &st, transport: g)
        XCTAssertEqual(o, .pushed); XCTAssertEqual(st.lastSyncedTs, 2000)
        // another device wrote in between -> abort
        g.content = data(n: 22, ts: 2500).serialized()
        o = await Sync.autoPush(local: data(n: 22, ts: 3000), state: &st, transport: g)
        if case .aborted = o {} else { XCTFail("\(o)") }
        // data-loss guard
        st.lastSyncedTs = 2500
        o = await Sync.autoPush(local: data(n: 5, ts: 3000), state: &st, transport: g)
        if case .blocked = o {} else { XCTFail("\(o)") }
        // offline
        g.failFetch = true
        o = await Sync.autoPush(local: data(n: 22, ts: 3100), state: &st, transport: g)
        if case .aborted = o {} else { XCTFail("\(o)") }
        XCTAssertEqual(g.pushes.count, 1)
    }
}

final class LocalStoreTests: XCTestCase {
    func testSaveLoadSnapshotsAndState() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("marley-test-\(UUID().uuidString)")
        let s = LocalStore(directory: dir)
        let d = makeData([T(1, "2026-11-01", "A", out: 1)], ts: 42)
        try s.save(d)
        XCTAssertEqual(s.load(), d)
        s.snapshot(d, reason: "pre-pull")
        XCTAssertEqual(s.backups().count, 2)
        var st = SyncState(lastSyncedTs: 42); st.hasSyncedThisSession = true
        s.saveState(st)
        XCTAssertEqual(s.loadState()?.lastSyncedTs, 42)
        XCTAssertEqual(s.loadState()?.hasSyncedThisSession, false) // never persisted
        try? FileManager.default.removeItem(at: dir)
    }
}
