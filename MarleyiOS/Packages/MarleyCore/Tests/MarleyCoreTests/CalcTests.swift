import XCTest
@testable import MarleyCore

final class CalcTests: XCTestCase {
    func testArithmetic() {
        XCTAssertEqual(Calc.evaluate("200-100"), 100)
        XCTAssertEqual(Calc.evaluate("200−100"), 100)
        XCTAssertEqual(Calc.evaluate("12,50+7,5"), 20)
        XCTAssertEqual(Calc.evaluate("10+2×3"), 16)          // precedência
        XCTAssertEqual(Calc.evaluate("(10+2)×3"), 36)
        XCTAssertEqual(Calc.evaluate("100÷3"), 33.33)        // arredonda a centavos
        XCTAssertEqual(Calc.evaluate("90/4"), 22.5)
        XCTAssertEqual(Calc.evaluate("2*3.5"), 7)
        XCTAssertEqual(Calc.evaluate("-50+20"), -30)
        XCTAssertEqual(Calc.evaluate(" 1 234 "), 1234)
        XCTAssertEqual(Calc.evaluate("21,24 €"), 21.24)
        XCTAssertEqual(Calc.evaluate("5-5"), 0)
        XCTAssertEqual(Calc.evaluate("0.1+0.2"), 0.3)
    }
    func testInvalidOrIncomplete() {
        for s in ["", "200-", "×3", "1,2,3", "(1+2", "1+2)", "abc", "10÷0", ",", "1..2"] { XCTAssertNil(Calc.evaluate(s), s) }
    }
    func testHelpers() {
        XCTAssertTrue(Calc.isExpression("200-100"))
        XCTAssertFalse(Calc.isExpression("-200"))
        XCTAssertFalse(Calc.isExpression("21,24"))
        XCTAssertEqual(Calc.format(100), "100,00")
        XCTAssertEqual(Calc.format(-3.5), "-3,50")
    }
}
