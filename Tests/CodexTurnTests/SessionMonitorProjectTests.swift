@testable import CodexTurnCore
import XCTest

@MainActor
final class SessionMonitorProjectTests: XCTestCase {
    func testRefreshReadsSessionsFromConfiguredCodexHomePath() async throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "monitor-custom-codex-home")
        defer { try? FileManager.default.removeItem(at: temp) }

        let customCodexHome = temp.appendingPathComponent("custom-codex", isDirectory: true)
        let sessionsDirectory = customCodexHome.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let now = Date()
        let sessionFile = sessionsDirectory.appendingPathComponent(
            "scan-d7cbf671-53ff-4a1f-b27b-b398e4a9e0fa.jsonl"
        )
        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-300)),
                    "payload": ["cwd": "/Users/me/project-from-setting"],
                ],
                [
                    "type": "response_item",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-120)),
                    "payload": ["role": "assistant"],
                ],
            ],
            to: sessionFile
        )

        let stateStore = ReminderStateStore(fileURL: temp.appendingPathComponent("state.json"))
        var settings = ReminderSettings.defaults
        settings.recencyWindowHours = 12
        settings.codexHomePath = customCodexHome.path
        stateStore.saveSettings(settings)

        let monitor = SessionMonitor(notifier: FakeNotifier(), stateStore: stateStore, autostart: false)

        await monitor.refresh()

        XCTAssertEqual(monitor.projects.count, 1)
        XCTAssertEqual(monitor.projects.first?.projectPath, "/Users/me/project-from-setting")
    }

    func testRefreshReadsScannerAndSortsByConversationTurnPriority() async throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "monitor-refresh")
        defer { try? FileManager.default.removeItem(at: temp) }

        let sessionsDirectory = temp.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

        let now = Date()
        let waitingFile = sessionsDirectory.appendingPathComponent(
            "scan-2b17f6c0-1908-4d95-a9af-2f48f40b8f41.jsonl"
        )
        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-1200)),
                    "payload": ["cwd": "/Users/me/project-waiting"],
                ],
                [
                    "type": "response_item",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-900)),
                    "payload": ["role": "user"],
                ],
            ],
            to: waitingFile
        )

        let activeFile = sessionsDirectory.appendingPathComponent(
            "scan-13066d4d-9493-401a-a01a-a23c1310f4a4.jsonl"
        )
        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-1000)),
                    "payload": ["cwd": "/Users/me/project-active"],
                ],
                [
                    "type": "response_item",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-700)),
                    "payload": ["role": "user"],
                ],
                [
                    "type": "response_item",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-600)),
                    "payload": ["role": "assistant"],
                ],
            ],
            to: activeFile
        )

        let stateStore = ReminderStateStore(fileURL: temp.appendingPathComponent("state.json"))
        let scanner = CodexHistoryScanner(initialFileCursors: [:], sessionsDirectory: sessionsDirectory)
        let monitor = SessionMonitor(
            notifier: FakeNotifier(),
            stateStore: stateStore,
            scanner: scanner,
            autostart: false
        )
        monitor.idleMinutes = 1
        monitor.reminderMinutes = 60

        await monitor.refresh()

        XCTAssertEqual(monitor.projects.count, 2)
        XCTAssertEqual(monitor.projects.first?.projectPath, "/Users/me/project-active")
        XCTAssertEqual(monitor.projects.first?.state, .active)
        XCTAssertTrue(monitor.projects.contains(where: { $0.projectPath == "/Users/me/project-waiting" }))
        XCTAssertEqual(monitor.statusText, "Tracking 2 project(s)")
        XCTAssertFalse(stateStore.allFileCursors().isEmpty)
    }

    func testEvaluateClearsWhenBelowIdleThreshold() async throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "monitor-idle")
        defer { try? FileManager.default.removeItem(at: temp) }

        let stateStore = ReminderStateStore(fileURL: temp.appendingPathComponent("state.json"))
        let notifier = FakeNotifier()
        let monitor = SessionMonitor(notifier: notifier, stateStore: stateStore, autostart: false)
        monitor.idleMinutes = 20

        let now = Date()
        let waitingSince = now.addingTimeInterval(-60)
        let project = ProjectGroup(
            id: "/Users/me/repo",
            displayName: "repo",
            projectPath: "/Users/me/repo",
            sessions: [
                SessionSnapshot(
                    sessionId: "s1",
                    cwd: "/Users/me/repo",
                    firstSeen: now.addingTimeInterval(-300),
                    latestEvent: waitingSince,
                    latestUserEvent: waitingSince,
                    latestAssistantEvent: nil,
                    latestUserSummary: nil
                ),
            ]
        )

        await monitor.evaluate(project: project, now: now)
        XCTAssertEqual(notifier.notifications.count, 0)
    }

    func testEvaluateSendsReminderWithCooldown() async throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "monitor")
        defer { try? FileManager.default.removeItem(at: temp) }

        let stateStore = ReminderStateStore(fileURL: temp.appendingPathComponent("state.json"))
        let notifier = FakeNotifier()
        let monitor = SessionMonitor(notifier: notifier, stateStore: stateStore, autostart: false)
        monitor.idleMinutes = 1
        monitor.reminderMinutes = 30

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let latestUser = now.addingTimeInterval(-900)
        let waitingSince = now.addingTimeInterval(-600)

        let project = ProjectGroup(
            id: "/Users/me/repo",
            displayName: "repo",
            projectPath: "/Users/me/repo",
            sessions: [
                SessionSnapshot(
                    sessionId: "s1",
                    cwd: "/Users/me/repo",
                    firstSeen: now.addingTimeInterval(-2_000),
                    latestEvent: waitingSince,
                    latestUserEvent: latestUser,
                    latestAssistantEvent: waitingSince,
                    latestUserSummary: nil
                ),
            ]
        )

        await monitor.evaluate(project: project, now: now)
        XCTAssertEqual(notifier.notifications.count, 1)

        await monitor.evaluate(project: project, now: now.addingTimeInterval(1_200))
        XCTAssertEqual(notifier.notifications.count, 1)

        await monitor.evaluate(project: project, now: now.addingTimeInterval(2_100))
        XCTAssertEqual(notifier.notifications.count, 2)
    }

    func testEvaluateClearsStoredWaitingStateForActiveProject() async throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "monitor")
        defer { try? FileManager.default.removeItem(at: temp) }

        let stateStore = ReminderStateStore(fileURL: temp.appendingPathComponent("state.json"))
        let notifier = FakeNotifier()
        let monitor = SessionMonitor(notifier: notifier, stateStore: stateStore, autostart: false)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        stateStore.recordNotification(
            projectPath: "/Users/me/repo",
            state: ProjectState.waiting.rawValue,
            stateFingerprint: "waiting-test",
            now: now
        )

        let activeProject = ProjectGroup(
            id: "/Users/me/repo",
            displayName: "repo",
            projectPath: "/Users/me/repo",
            sessions: [
                SessionSnapshot(
                    sessionId: "s1",
                    cwd: "/Users/me/repo",
                    firstSeen: now.addingTimeInterval(-2_000),
                    latestEvent: now,
                    latestUserEvent: now.addingTimeInterval(-600),
                    latestAssistantEvent: now.addingTimeInterval(-300),
                    latestUserSummary: nil
                ),
            ]
        )

        await monitor.evaluate(project: activeProject, now: now)
        XCTAssertEqual(notifier.notifications.count, 0)
        XCTAssertTrue(
            stateStore.shouldNotify(
                projectPath: "/Users/me/repo",
                stateFingerprint: "waiting-test",
                interval: 10_000,
                now: now
            )
        )
    }

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

    func testProjectStateText() {
        let temp = try? TestSupport.makeTemporaryDirectory(prefix: "monitor")
        defer {
            if let temp {
                try? FileManager.default.removeItem(at: temp)
            }
        }

        let fallbackDirectory = temp ?? FileManager.default.temporaryDirectory
        let stateStore = ReminderStateStore(
            fileURL: fallbackDirectory.appendingPathComponent("state.json")
        )
        let monitor = SessionMonitor(notifier: FakeNotifier(), stateStore: stateStore, autostart: false)
        let now = Date()

        let waitingProject = ProjectGroup(
            id: "w",
            displayName: "w",
            projectPath: "/Users/me/w",
            sessions: [
                SessionSnapshot(
                    sessionId: "w1",
                    cwd: "/Users/me/w",
                    firstSeen: now.addingTimeInterval(-300),
                    latestEvent: now.addingTimeInterval(-120),
                    latestUserEvent: now.addingTimeInterval(-120),
                    latestAssistantEvent: nil,
                    latestUserSummary: nil
                ),
            ]
        )
        XCTAssertTrue(monitor.projectStateText(waitingProject).contains("Assistant turn"))

        let activeProject = ProjectGroup(
            id: "a",
            displayName: "a",
            projectPath: "/Users/me/a",
            sessions: [
                SessionSnapshot(
                    sessionId: "a1",
                    cwd: "/Users/me/a",
                    firstSeen: now.addingTimeInterval(-300),
                    latestEvent: now.addingTimeInterval(-60),
                    latestUserEvent: now.addingTimeInterval(-120),
                    latestAssistantEvent: now.addingTimeInterval(-60),
                    latestUserSummary: nil
                ),
            ]
        )
        XCTAssertTrue(monitor.projectStateText(activeProject).contains("Your turn"))

        let idleProject = ProjectGroup(
            id: "i",
            displayName: "idle",
            projectPath: "/Users/me/i",
            sessions: []
        )
        XCTAssertEqual(monitor.projectStateText(idleProject), "Dormant")
    }
}
