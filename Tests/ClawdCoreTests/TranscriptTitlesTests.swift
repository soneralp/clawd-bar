import XCTest
@testable import ClawdCore

final class TranscriptTitlesTests: XCTestCase {
    private var file: URL!

    override func setUp() {
        super.setUp()
        file = FileManager.default.temporaryDirectory.appendingPathComponent("transcript-\(UUID().uuidString).jsonl")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: file)
        super.tearDown()
    }

    private func write(_ lines: [String]) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    private let message = #"{"type":"user","message":{"content":"hello"}}"#

    func testReadsLatestCustomAndAITitles() throws {
        try write([
            #"{"type":"ai-title","aiTitle":"Old title","sessionId":"s"}"#,
            message,
            #"{"type":"custom-title","customTitle":"Release prep","sessionId":"s"}"#,
            #"{"type":"ai-title","aiTitle":"Café menu redesign","sessionId":"s"}"#,
        ])
        let titles = TranscriptTitles.read(from: file)
        XCTAssertEqual(titles.custom, "Release prep")
        XCTAssertEqual(titles.ai, "Café menu redesign")
    }

    func testMissingFileReturnsNothing() {
        let titles = TranscriptTitles.read(from: file)
        XCTAssertNil(titles.custom)
        XCTAssertNil(titles.ai)
    }

    func testOnlyReadsTheTail() throws {
        let filler = Array(repeating: message, count: 2_000)
        try write([#"{"type":"custom-title","customTitle":"Too far back","sessionId":"s"}"#] + filler
                  + [#"{"type":"ai-title","aiTitle":"Recent","sessionId":"s"}"#])
        let titles = TranscriptTitles.read(from: file, tailBytes: 4_096)
        XCTAssertNil(titles.custom)
        XCTAssertEqual(titles.ai, "Recent")
    }

    func testIgnoresPartialFirstLineAndMalformedEntries() throws {
        let long = #"{"type":"custom-title","customTitle":"Cut off \#(String(repeating: "x", count: 200))","sessionId":"s"}"#
        try write([long, #"{"type":"ai-title","aiTitle":42}"#, #"{"type":"ai-title""#, message])
        let titles = TranscriptTitles.read(from: file, tailBytes: 150)
        XCTAssertNil(titles.custom)
        XCTAssertNil(titles.ai)
    }

    func testBlankTitlesAreIgnored() throws {
        try write([#"{"type":"custom-title","customTitle":"   ","sessionId":"s"}"#])
        XCTAssertNil(TranscriptTitles.read(from: file).custom)
    }
}
