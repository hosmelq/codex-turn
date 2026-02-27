@testable import CodexTurnCore
import XCTest

@MainActor
final class SessionMonitorMemoryFilterTests: XCTestCase {
    func testRefreshIgnoresCodexMemoriesSessions() async throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "monitor-ignore-memories")
        defer { try? FileManager.default.removeItem(at: temp) }

        let customCodexHome = temp.appendingPathComponent("custom-codex", isDirectory: true)
        let sessionsDirectory = customCodexHome.appendingPathComponent("sessions", isDirectory: true)
        let memoriesDirectory = customCodexHome.appendingPathComponent("memories", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: memoriesDirectory, withIntermediateDirectories: true)

        let now = Date()
        let memorySessionFile = sessionsDirectory.appendingPathComponent(
            "scan-4f1e73f1-9573-4bb5-9065-e63385b83f4b.jsonl"
        )
        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-300)),
                    "payload": ["cwd": memoriesDirectory.path],
                ],
                [
                    "type": "response_item",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-120)),
                    "payload": [
                        "role": "assistant",
                        "content": [["text": "## Memory Writing Agent: Phase 2", "type": "input_text"]],
                    ],
                ],
            ],
            to: memorySessionFile
        )

        let projectSessionFile = sessionsDirectory.appendingPathComponent(
            "scan-5f48c43b-cf31-4138-8107-e04589f6e447.jsonl"
        )
        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-280)),
                    "payload": ["cwd": "/Users/me/mission-control"],
                ],
                [
                    "type": "response_item",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-100)),
                    "payload": [
                        "role": "assistant",
                        "content": [["text": "Done", "type": "input_text"]],
                    ],
                ],
            ],
            to: projectSessionFile
        )

        let stateStore = ReminderStateStore(fileURL: temp.appendingPathComponent("state.json"))
        var settings = ReminderSettings.defaults
        settings.recencyWindowHours = 12
        settings.codexHomePath = customCodexHome.path
        stateStore.saveSettings(settings)

        let monitor = SessionMonitor(notifier: FakeNotifier(), stateStore: stateStore, autostart: false)

        await monitor.refresh()

        XCTAssertEqual(monitor.projects.count, 1)
        XCTAssertEqual(monitor.projects.first?.projectPath, "/Users/me/mission-control")
        XCTAssertFalse(monitor.projects.contains(where: { $0.displayName == "memories" }))
    }
}
