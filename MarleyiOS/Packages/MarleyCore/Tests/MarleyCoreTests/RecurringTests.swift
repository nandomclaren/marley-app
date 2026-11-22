import XCTest
@testable import MarleyCore

final class RecurringTests: XCTestCase {
    /// Netflix todo dia 04 de setembro a janeiro; setembro reconciliado. Outra conta com a mesma descrição não entra.
    func data() -> AppData {
        var txns = ["2026-09", "2026-10", "2026-11", "2026-12", "2027-01"].enumerated().map { i, m in
            T(i + 1, "\(m)-04", "Netflix", out: 7.36, cat: "💻 Abonnements", style: "fixed", locked: m == "2026-09")
        }
        txns.append(T(50, "2026-11-04", "Netflix", acct: "Wise", out: 9, style: "fixed"))
        txns.append(T(51, "2026-11-05", "Pão", out: 2))
        return makeData(txns, months: ["2026-09", "2026-10", "2026-11", "2026-12", "2027-01"])
    }
    func netflix(_ d: AppData) -> [Txn] { d.txns.filter { $0.desc.hasPrefix("Netflix") && $0.acct == "Revolut" }.sorted { $0.date < $1.date } }
    func edit(_ t: Txn, amount: Double? = nil, day: Int? = nil, desc: String? = nil) -> TxnEdit {
        TxnEdit(date: day.map { String(format: "%@-%02d", t.month, $0) } ?? t.date, desc: desc ?? t.desc, acct: t.acct,
                amount: amount ?? t.amount, isIncome: false, cat: t.cat, notes: t.notes, recurring: true, uncertain: false)
    }

    func testSeriesAndOthers() {
        let d = data(), nov = d.txn(3)!
        XCTAssertEqual(Recurring.series(d, nov).map(\.id), [1, 2, 3, 4, 5])
        XCTAssertEqual(Recurring.others(d, nov, .thisAndFuture).map(\.id), [4, 5])
        XCTAssertEqual(Recurring.others(d, nov, .all).map(\.id), [2, 4, 5]) // setembro reconciliado fica de fora
        XCTAssertTrue(Recurring.hasOthers(d, nov))
        XCTAssertFalse(Recurring.hasOthers(d, d.txn(51)!))
    }
    func testEditThisOnly() {
        var d = data()
        Recurring.applyEdit(&d, original: d.txn(3)!, edit: edit(d.txn(3)!, amount: 9.99), scope: .this)
        XCTAssertEqual(netflix(d).map(\.out), [7.36, 7.36, 9.99, 7.36, 7.36])
    }
    func testEditThisAndFutureChangesOnlyChangedFieldsAndDay() {
        var d = data()
        Recurring.applyEdit(&d, original: d.txn(2)!, edit: edit(d.txn(2)!, amount: 9.99, day: 31), scope: .thisAndFuture)
        let n = netflix(d)
        XCTAssertEqual(n.map(\.out), [7.36, 9.99, 9.99, 9.99, 9.99])
        XCTAssertEqual(n.map(\.date), ["2026-09-04", "2026-10-31", "2026-11-30", "2026-12-31", "2027-01-31"]) // dia limitado ao fim do mês
        XCTAssertTrue(n.allSatisfy { $0.cat == "💻 Abonnements" })
        XCTAssertEqual(d.txn(50)?.out, 9) // outra conta intacta
    }
    func testEditAllNeverTouchesReconciled() {
        var d = data()
        Recurring.applyEdit(&d, original: d.txn(3)!, edit: edit(d.txn(3)!, amount: 9.99, desc: "Netflix Premium"), scope: .all)
        let n = netflix(d)
        XCTAssertEqual(n.map(\.desc), ["Netflix", "Netflix Premium", "Netflix Premium", "Netflix Premium", "Netflix Premium"])
        XCTAssertEqual(n.first!.out, 7.36); XCTAssertTrue(n.first!.locked)
    }
    func testDeleteThisAndFutureStopsTheSeries() {
        var d = data()
        Recurring.delete(&d, d.txn(3)!, scope: .thisAndFuture)
        XCTAssertEqual(netflix(d).map(\.id), [1, 2])
        // ao revisitar os meses, nada é recriado
        for m in ["2026-11", "2026-12", "2027-01"] { Ledger.generateRecurring(&d, month: m) }
        XCTAssertEqual(netflix(d).map(\.id), [1, 2])
        // nem num mês novo criado depois
        var months = d.months; months.append("2027-02"); d.months = months
        XCTAssertEqual(Ledger.generateRecurring(&d, month: "2027-02"), 0)
    }
    func testDeleteAllKeepsReconciledButEndsRecurrence() {
        var d = data()
        Recurring.delete(&d, d.txn(3)!, scope: .all)
        let n = netflix(d)
        XCTAssertEqual(n.map(\.id), [1])
        XCTAssertTrue(n[0].locked); XCTAssertFalse(n[0].isRecurringKind)
        for m in ["2026-10", "2026-11", "2026-12", "2027-01"] { Ledger.generateRecurring(&d, month: m) }
        XCTAssertEqual(netflix(d).count, 1)
        XCTAssertNotNil(d.txn(50)); XCTAssertNotNil(d.txn(51))
    }
    func testDeleteThisOnlySkipsJustThatMonth() {
        var d = data()
        Recurring.delete(&d, d.txn(3)!, scope: .this)
        XCTAssertEqual(netflix(d).map(\.id), [1, 2, 4, 5])
        XCTAssertEqual(Ledger.generateRecurring(&d, month: "2026-11"), 0)
    }
}
