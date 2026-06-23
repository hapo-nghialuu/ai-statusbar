import XCTest
@testable import AIStatusbar

final class ProviderStatusTests: XCTestCase {
    func testQuotaWindowRoundTrip() throws {
        let w = QuotaWindow(label: "5 giờ", usedPct: 20, remainingPct: 80)
        let data = try JSONEncoder().encode(w)
        let decoded = try JSONDecoder().decode(QuotaWindow.self, from: data)
        XCTAssertEqual(w.label, decoded.label)
        XCTAssertEqual(w.usedPct, decoded.usedPct)
        XCTAssertEqual(w.remainingPct, decoded.remainingPct)
    }

    func testProviderStatusWindowsPreserveOrder() throws {
        let s = ProviderStatus(
            id: "minimax",
            displayName: "MiniMax",
            windows: [
                QuotaWindow(label: "5 giờ", usedPct: 20, remainingPct: 80),
                QuotaWindow(label: "Tuần", usedPct: 40, remainingPct: 60)
            ],
            lastUpdated: Date(timeIntervalSince1970: 1700000000)
        )
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(ProviderStatus.self, from: data)
        XCTAssertEqual(decoded.windows.count, 2)
        XCTAssertEqual(decoded.windows[0].label, "5 giờ")
        XCTAssertEqual(decoded.windows[1].label, "Tuần")
    }

    func testErrorFieldRoundTripsNilAndString() throws {
        let nilErr = ProviderStatus(id: "x", displayName: "X", windows: [], lastUpdated: Date(), error: nil)
        let someErr = ProviderStatus(id: "x", displayName: "X", windows: [], lastUpdated: Date(), error: "boom")
        let d1 = try JSONDecoder().decode(ProviderStatus.self, from: try JSONEncoder().encode(nilErr))
        let d2 = try JSONDecoder().decode(ProviderStatus.self, from: try JSONEncoder().encode(someErr))
        XCTAssertNil(d1.error)
        XCTAssertEqual(d2.error, "boom")
    }
}
