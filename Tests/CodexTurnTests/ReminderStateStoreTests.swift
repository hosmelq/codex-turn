@testable import CodexTurnCore
import XCTest

final class ReminderStateStoreTests: XCTestCase {
    func testNotificationStateLifecycle() throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "state")
        defer { try? FileManager.default.removeItem(at: temp) }
        let fileURL = temp.appendingPathComponent("reminder_state.json")
        let store = ReminderStateStore(fileURL: fileURL)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertTrue(store.shouldNotify(projectPath: "/tmp/p", stateFingerprint: "f1", interval: 60, now: now))

        store.recordNotification(
            projectPath: "/tmp/p",
            state: ProjectState.waiting.rawValue,
            stateFingerprint: "f1",
            now: now
        )

        XCTAssertFalse(
            store.shouldNotify(
                projectPath: "/tmp/p",
                stateFingerprint: "f1",
                interval: 60,
                now: now.addingTimeInterval(30)
            )
        )

        XCTAssertTrue(
            store.shouldNotify(
                projectPath: "/tmp/p",
                stateFingerprint: "f1",
                interval: 60,
                now: now.addingTimeInterval(120)
            )
        )

        store.clearProject(projectPath: "/tmp/p")
        XCTAssertTrue(store.shouldNotify(projectPath: "/tmp/p", stateFingerprint: "f1", interval: 60, now: now))
    }

    func testCursorPersistence() throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "state")
        defer { try? FileManager.default.removeItem(at: temp) }
        let fileURL = temp.appendingPathComponent("reminder_state.json")

        let store = ReminderStateStore(fileURL: fileURL)

        let cursor = FileScanCursor(
            offset: 10,
            fileSize: 100,
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        store.updateFileCursors(["/tmp/sessions.jsonl": cursor])

        let reloaded = ReminderStateStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.allFileCursors()["/tmp/sessions.jsonl"], cursor)
    }

    func testSettingsRoundTripPersistence() throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "state")
        defer { try? FileManager.default.removeItem(at: temp) }
        let fileURL = temp.appendingPathComponent("reminder_state.json")

        let store = ReminderStateStore(fileURL: fileURL)
        let settings = ReminderSettings(
            idleMinutes: 12,
            pollSeconds: 15,
            recencyWindowHours: 8,
            reminderMinutes: 45,
            useRepoRoot: false,
            codexHomePath: "/Users/me/custom-codex"
        )
        store.saveSettings(settings)

        let reloaded = ReminderStateStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.loadSettings(), settings)
    }

    func testSettingsClampOutOfBoundsValuesOnSaveAndLoad() throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "state")
        defer { try? FileManager.default.removeItem(at: temp) }
        let fileURL = temp.appendingPathComponent("reminder_state.json")

        let store = ReminderStateStore(fileURL: fileURL)
        store.saveSettings(
            ReminderSettings(
                idleMinutes: -5,
                pollSeconds: 1,
                recencyWindowHours: 100,
                reminderMinutes: 999,
                useRepoRoot: true,
                codexHomePath: nil
            )
        )

        let reloaded = ReminderStateStore(fileURL: fileURL)
        let settings = reloaded.loadSettings()
        XCTAssertEqual(settings.idleMinutes, 1)
        XCTAssertEqual(settings.pollSeconds, 10)
        XCTAssertEqual(settings.recencyWindowHours, 24)
        XCTAssertEqual(settings.reminderMinutes, 120)
    }
}
