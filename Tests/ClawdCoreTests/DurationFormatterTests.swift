import XCTest
@testable import ClawdCore

final class DurationFormatterTests: XCTestCase {
    func testElapsedSeconds() {
        XCTAssertEqual(DurationFormatter.elapsed(12), "12s")
        XCTAssertEqual(DurationFormatter.elapsed(0), "0s")
        XCTAssertEqual(DurationFormatter.elapsed(59.9), "59s")
    }

    func testElapsedMinutes() {
        XCTAssertEqual(DurationFormatter.elapsed(60), "1m")
        XCTAssertEqual(DurationFormatter.elapsed(240), "4m")
        XCTAssertEqual(DurationFormatter.elapsed(3599), "59m")
    }

    func testElapsedHours() {
        XCTAssertEqual(DurationFormatter.elapsed(3600), "1h 0m")
        XCTAssertEqual(DurationFormatter.elapsed(4320), "1h 12m")
    }

    func testAgo() {
        XCTAssertEqual(DurationFormatter.ago(30), "just now")
        XCTAssertEqual(DurationFormatter.ago(480), "8m ago")
        XCTAssertEqual(DurationFormatter.ago(7200), "2h ago")
        XCTAssertEqual(DurationFormatter.ago(7200 + 1800), "2h ago")
    }

    func testNegativeClampsToZero() {
        XCTAssertEqual(DurationFormatter.elapsed(-5), "0s")
        XCTAssertEqual(DurationFormatter.ago(-5), "just now")
    }
}
