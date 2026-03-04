@testable import CodexTurnCore
import XCTest

@MainActor
final class SessionMonitorThreadPresentationTests: XCTestCase {
    func testSessionContextLineShowsCodexForCodexCliSessions() throws {
        let monitor = try makeMonitor()
        let context = monitor.sessionContextLine(
            snapshot(
                cwd: "/Users/me/project",
                originator: "codex_cli_rs",
                source: "cli"
            )
        )

        XCTAssertTrue(context.contains("main"))
        XCTAssertTrue(context.contains("Codex CLI"))
        XCTAssertFalse(context.contains("Desktop"))
    }

    func testSessionContextLineShowsPolyscopeAsAppName() throws {
        let monitor = try makeMonitor()
        let context = monitor.sessionContextLine(
            snapshot(
                cwd: "/Users/me/.polyscope/clones/5ce5359f/emerald-walrus",
                originator: "codex_sdk_ts",
                source: "exec"
            )
        )

        XCTAssertTrue(context.contains("Polyscope"))
        XCTAssertFalse(context.contains("via"))
        XCTAssertFalse(context.contains("Codex"))
    }

    func testSessionContextLineShowsOpencodeAsAppNameFromWorktreePath() throws {
        let monitor = try makeMonitor()
        let context = monitor.sessionContextLine(
            snapshot(
                cwd: "/Users/me/.local/share/opencode/worktree/abc123/jolly-moon",
                originator: "codex_cli_rs",
                source: "cli"
            )
        )

        XCTAssertTrue(context.contains("Opencode CLI"))
        XCTAssertFalse(context.contains("Codex CLI"))
    }

    func testSessionContextLineShowsCliWhenOnlySourceIsKnown() throws {
        let monitor = try makeMonitor()
        let context = monitor.sessionContextLine(
            snapshot(
                cwd: "/Users/me/project",
                originator: nil,
                source: "cli"
            )
        )

        XCTAssertTrue(context.contains("CLI"))
    }

    func testSessionContextLineShowsNonCodexOriginatorFamilyAsAppName() throws {
        let monitor = try makeMonitor()
        let context = monitor.sessionContextLine(
            snapshot(
                cwd: "/Users/me/project",
                originator: "repoprompt",
                source: "exec"
            )
        )

        XCTAssertTrue(context.contains("Repoprompt"))
    }

    private func makeMonitor() throws -> SessionMonitor {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "monitor-thread-context")
        addTeardownBlock { try? FileManager.default.removeItem(at: temp) }
        let stateStore = ReminderStateStore(fileURL: temp.appendingPathComponent("state.json"))
        return SessionMonitor(notifier: FakeNotifier(), stateStore: stateStore, autostart: false)
    }

    private func snapshot(
        cwd: String,
        originator: String?,
        source: String?
    ) -> SessionSnapshot {
        let now = Date()
        return SessionSnapshot(
            sessionId: "session-1",
            cwd: cwd,
            firstSeen: now.addingTimeInterval(-300),
            gitBranch: "main",
            latestEvent: now.addingTimeInterval(-60),
            latestUserEvent: now.addingTimeInterval(-120),
            latestAssistantEvent: now.addingTimeInterval(-60),
            latestUserSummary: nil,
            latestAssistantSummary: nil,
            originator: originator,
            sessionLogPath: nil,
            source: source
        )
    }
}
