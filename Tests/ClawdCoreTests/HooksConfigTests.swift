import XCTest
@testable import ClawdCore

final class HooksConfigTests: XCTestCase {
    private let command = "~/.claude/clawd-bar/bin/clawd-hook"

    private func hooks(_ settings: [String: Any]) -> [String: [[String: Any]]] {
        settings["hooks"] as? [String: [[String: Any]]] ?? [:]
    }

    private func commands(in entries: [[String: Any]]) -> [String] {
        entries.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    private let foreignStop: [String: Any] = [
        "model": "x",
        "hooks": ["Stop": [["hooks": [["type": "command", "command": "other"]]]]],
    ]

    func testInstallIntoEmptySettingsAddsAllEvents() throws {
        let result = HooksConfig.install(into: [:], command: command)
        let installed = hooks(result)
        XCTAssertEqual(Set(installed.keys), Set(HooksConfig.events.map(\.event)))
        XCTAssertEqual(installed.count, 12)
        let preToolUse = try XCTUnwrap(installed["PreToolUse"]?.first)
        XCTAssertEqual(preToolUse["matcher"] as? String, "AskUserQuestion")
        XCTAssertNil(installed["Stop"]?.first?["matcher"])
        let hook = try XCTUnwrap((installed["Stop"]?.first?["hooks"] as? [[String: Any]])?.first)
        XCTAssertEqual(hook["type"] as? String, "command")
        XCTAssertEqual(hook["command"] as? String, command)
    }

    func testInstallPreservesExistingHooks() {
        let result = HooksConfig.install(into: foreignStop, command: command)
        XCTAssertEqual(result["model"] as? String, "x")
        XCTAssertEqual(commands(in: hooks(result)["Stop"] ?? []), ["other", command])
    }

    func testInstallIsIdempotent() {
        let once = HooksConfig.install(into: foreignStop, command: command)
        let twice = HooksConfig.install(into: once, command: command)
        XCTAssertEqual(NSDictionary(dictionary: once), NSDictionary(dictionary: twice))
    }

    func testRemoveOnlyRemovesOurs() {
        let installed = HooksConfig.install(into: foreignStop, command: command)
        let removed = HooksConfig.remove(from: installed, command: command)
        XCTAssertEqual(Array(hooks(removed).keys), ["Stop"])
        XCTAssertEqual(commands(in: hooks(removed)["Stop"] ?? []), ["other"])
        XCTAssertEqual(removed["model"] as? String, "x")
    }

    func testRemoveDropsEmptyHooksKey() {
        let installed = HooksConfig.install(into: ["model": "x"], command: command)
        let removed = HooksConfig.remove(from: installed, command: command)
        XCTAssertNil(removed["hooks"])
        XCTAssertEqual(removed["model"] as? String, "x")
    }

    func testIsInstalled() {
        XCTAssertFalse(HooksConfig.isInstalled([:], command: command))
        XCTAssertTrue(HooksConfig.isInstalled(HooksConfig.install(into: [:], command: command), command: command))
    }

    func testIsInstalledFalseWhenPartial() {
        let partial: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": command]]]]]]
        XCTAssertFalse(HooksConfig.isInstalled(partial, command: command))
    }

    func testMalformedValuesArePassedThroughUntouched() {
        let malformed: [String: Any] = ["hooks": ["Stop": "oops", "SessionEnd": [42], "Custom": ["x": 1]]]
        let installed = HooksConfig.install(into: malformed, command: command)
        let table = installed["hooks"] as? [String: Any] ?? [:]
        XCTAssertEqual(table["Stop"] as? String, "oops")
        XCTAssertEqual((table["SessionEnd"] as? [Any])?.first as? Int, 42)
        XCTAssertEqual((table["SessionEnd"] as? [Any])?.count, 2)
        XCTAssertNotNil(table["Custom"])

        let removed = HooksConfig.remove(from: installed, command: command)
        let after = removed["hooks"] as? [String: Any] ?? [:]
        XCTAssertEqual(after["Stop"] as? String, "oops")
        XCTAssertEqual((after["SessionEnd"] as? [Any])?.count, 1)
        XCTAssertNotNil(after["Custom"])
    }

    func testRemoveLeavesNonDictionaryHooksAlone() {
        let odd: [String: Any] = ["hooks": "nonsense"]
        XCTAssertEqual(HooksConfig.remove(from: odd, command: command)["hooks"] as? String, "nonsense")
    }

    func testPreservesEmptyEventArraysWeDidNotTouch() {
        let settings: [String: Any] = ["hooks": ["Custom": [Any]()]]
        let removed = HooksConfig.remove(from: settings, command: command)
        XCTAssertNotNil((removed["hooks"] as? [String: Any])?["Custom"])
    }
}
