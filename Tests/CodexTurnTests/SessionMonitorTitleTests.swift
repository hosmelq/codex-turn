@testable import CodexTurnCore
import XCTest

@MainActor
final class SessionMonitorTitleTests: XCTestCase {
    func testSessionTitlePrefersLatestTurnSummary() throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "monitor-title")
        defer { try? FileManager.default.removeItem(at: temp) }

        let stateStore = ReminderStateStore(fileURL: temp.appendingPathComponent("state.json"))
        let monitor = SessionMonitor(notifier: FakeNotifier(), stateStore: stateStore, autostart: false)
        let now = Date()

        let assistantLatest = SessionSnapshot(
            sessionId: "session-assistant",
            cwd: "/Users/me/project",
            firstSeen: now.addingTimeInterval(-300),
            latestEvent: now.addingTimeInterval(-60),
            latestUserEvent: now.addingTimeInterval(-120),
            latestAssistantEvent: now.addingTimeInterval(-60),
            latestUserSummary: "How are you?",
            latestAssistantSummary: "Doing well — anything else you need?"
        )
        XCTAssertEqual(
            monitor.sessionTitle(assistantLatest),
            "Doing well — anything else you need?"
        )

        let userLatest = SessionSnapshot(
            sessionId: "session-user",
            cwd: "/Users/me/project",
            firstSeen: now.addingTimeInterval(-300),
            latestEvent: now.addingTimeInterval(-30),
            latestUserEvent: now.addingTimeInterval(-30),
            latestAssistantEvent: now.addingTimeInterval(-60),
            latestUserSummary: "Can you check the API logs?",
            latestAssistantSummary: "Sure, checking now."
        )
        XCTAssertEqual(
            monitor.sessionTitle(userLatest),
            "Can you check the API logs?"
        )
    }

    func testSessionTitleExtractsHumanSummaryFromJsonPayload() throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "monitor-title-json")
        defer { try? FileManager.default.removeItem(at: temp) }

        let stateStore = ReminderStateStore(fileURL: temp.appendingPathComponent("state.json"))
        let monitor = SessionMonitor(notifier: FakeNotifier(), stateStore: stateStore, autostart: false)
        let now = Date()

        let assistantLatest = SessionSnapshot(
            sessionId: "session-json-summary",
            cwd: "/Users/me/project",
            firstSeen: now.addingTimeInterval(-300),
            latestEvent: now.addingTimeInterval(-60),
            latestUserEvent: now.addingTimeInterval(-120),
            latestAssistantEvent: now.addingTimeInterval(-60),
            latestUserSummary: nil,
            latestAssistantSummary:
                #"{"findings":[{"title":"[P1] Add session title fallback for structured output"}]}"#
        )

        XCTAssertEqual(
            monitor.sessionTitle(assistantLatest),
            "[P1] Add session title fallback for structured output"
        )
    }

    func testSessionTitleExtractsTitleFromTruncatedJsonPayload() throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "monitor-title-json-truncated")
        defer { try? FileManager.default.removeItem(at: temp) }

        let stateStore = ReminderStateStore(fileURL: temp.appendingPathComponent("state.json"))
        let monitor = SessionMonitor(notifier: FakeNotifier(), stateStore: stateStore, autostart: false)
        let now = Date()

        let assistantLatest = SessionSnapshot(
            sessionId: "session-json-summary-truncated",
            cwd: "/Users/me/project",
            firstSeen: now.addingTimeInterval(-300),
            latestEvent: now.addingTimeInterval(-60),
            latestUserEvent: now.addingTimeInterval(-120),
            latestAssistantEvent: now.addingTimeInterval(-60),
            latestUserSummary: nil,
            latestAssistantSummary: #"{"findings":[{"title":"[P1] Add summary sanitizer"}]..."#
        )

        XCTAssertEqual(
            monitor.sessionTitle(assistantLatest),
            "[P1] Add summary sanitizer"
        )
    }

    func testSessionTitleExtractsTitleFromTruncatedJsonPayloadWithoutClosingQuote() throws {
        let temp = try TestSupport.makeTemporaryDirectory(
            prefix: "monitor-title-json-truncated-missing-quote"
        )
        defer { try? FileManager.default.removeItem(at: temp) }

        let stateStore = ReminderStateStore(fileURL: temp.appendingPathComponent("state.json"))
        let monitor = SessionMonitor(notifier: FakeNotifier(), stateStore: stateStore, autostart: false)
        let now = Date()

        let assistantLatest = SessionSnapshot(
            sessionId: "session-json-summary-truncated-open",
            cwd: "/Users/me/project",
            firstSeen: now.addingTimeInterval(-300),
            latestEvent: now.addingTimeInterval(-60),
            latestUserEvent: now.addingTimeInterval(-120),
            latestAssistantEvent: now.addingTimeInterval(-60),
            latestUserSummary: nil,
            latestAssistantSummary: #"{ "findings": [ { "title": "[P2] Improve scanner fallback handling..."#
        )

        XCTAssertEqual(
            monitor.sessionTitle(assistantLatest),
            "[P2] Improve scanner fallback handling..."
        )
    }

    func testSessionTitleDoesNotDisplayRawStructuredArrayFallback() throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "monitor-title-json-no-candidate")
        defer { try? FileManager.default.removeItem(at: temp) }

        let stateStore = ReminderStateStore(fileURL: temp.appendingPathComponent("state.json"))
        let monitor = SessionMonitor(notifier: FakeNotifier(), stateStore: stateStore, autostart: false)
        let now = Date()

        let assistantLatest = SessionSnapshot(
            sessionId: "session-json-summary-no-candidate",
            cwd: "/Users/me/project",
            firstSeen: now.addingTimeInterval(-300),
            latestEvent: now.addingTimeInterval(-60),
            latestUserEvent: now.addingTimeInterval(-120),
            latestAssistantEvent: now.addingTimeInterval(-60),
            latestUserSummary: nil,
            latestAssistantSummary: #"[{"priority":2,"confidence":0.93}]"#
        )

        let title = monitor.sessionTitle(assistantLatest)
        XCTAssertTrue(title.hasPrefix("Thread "))
        XCTAssertFalse(title.contains(#"{"#))
        XCTAssertFalse(title.contains(#"["#))
    }

    func testSessionTitlePreservesBracketPrefixedPlainSummary() throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "monitor-title-plain-bracket")
        defer { try? FileManager.default.removeItem(at: temp) }

        let stateStore = ReminderStateStore(fileURL: temp.appendingPathComponent("state.json"))
        let monitor = SessionMonitor(notifier: FakeNotifier(), stateStore: stateStore, autostart: false)
        let now = Date()

        let assistantLatest = SessionSnapshot(
            sessionId: "session-plain-summary",
            cwd: "/Users/me/project",
            firstSeen: now.addingTimeInterval(-300),
            latestEvent: now.addingTimeInterval(-60),
            latestUserEvent: now.addingTimeInterval(-120),
            latestAssistantEvent: now.addingTimeInterval(-60),
            latestUserSummary: nil,
            latestAssistantSummary: "[P1] Fix login flow"
        )

        XCTAssertEqual(
            monitor.sessionTitle(assistantLatest),
            "[P1] Fix login flow"
        )
    }
}
