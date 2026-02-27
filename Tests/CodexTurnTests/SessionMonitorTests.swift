@testable import CodexTurnCore
import XCTest

@MainActor
final class SessionMonitorTests: XCTestCase {
    func testRequestNotificationPermissionUpdatesState() async throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "monitor")
        defer { try? FileManager.default.removeItem(at: temp) }

        let successMonitor = SessionMonitor(
            notifier: FakeNotifier(),
            stateStore: ReminderStateStore(fileURL: temp.appendingPathComponent("success.json")),
            autostart: false
        )
        await successMonitor.requestNotificationPermission()
        XCTAssertTrue(successMonitor.hasPermission)
        XCTAssertEqual(successMonitor.statusText, "Notifications enabled")

        let warmupFailureMonitor = SessionMonitor(
            notifier: WarmupFailingNotifier(),
            stateStore: ReminderStateStore(fileURL: temp.appendingPathComponent("warmup-failure.json")),
            autostart: false
        )
        await warmupFailureMonitor.requestNotificationPermission()
        XCTAssertTrue(warmupFailureMonitor.hasPermission)
        XCTAssertEqual(warmupFailureMonitor.statusText, "Notifications enabled (delivery check failed)")

        let failureMonitor = SessionMonitor(
            notifier: FailingNotifier(),
            stateStore: ReminderStateStore(fileURL: temp.appendingPathComponent("failure.json")),
            autostart: false
        )
        await failureMonitor.requestNotificationPermission()
        XCTAssertFalse(failureMonitor.hasPermission)
        XCTAssertEqual(failureMonitor.statusText, "Notification permission required")
    }

    func testSendTestNotificationUpdatesStateAndCallsNotifier() async throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "monitor-notification-test")
        defer { try? FileManager.default.removeItem(at: temp) }

        let successNotifier = FakeNotifier()
        let successMonitor = SessionMonitor(
            notifier: successNotifier,
            stateStore: ReminderStateStore(fileURL: temp.appendingPathComponent("success-state.json")),
            autostart: false
        )

        await successMonitor.sendTestNotification()
        XCTAssertEqual(successNotifier.requestPermissionCalls, 1)
        XCTAssertEqual(successNotifier.notifications.count, 1)
        XCTAssertTrue(successMonitor.hasPermission)
        XCTAssertEqual(successMonitor.statusText, "Sent test notification")

        let failureMonitor = SessionMonitor(
            notifier: FailingNotifier(),
            stateStore: ReminderStateStore(fileURL: temp.appendingPathComponent("failure-state.json")),
            autostart: false
        )
        await failureMonitor.sendTestNotification()
        XCTAssertFalse(failureMonitor.hasPermission)
        XCTAssertEqual(failureMonitor.statusText, "Notification permission required")
    }

    func testMonitorLoadsPersistedSettingsOnInit() throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "monitor-settings")
        defer { try? FileManager.default.removeItem(at: temp) }
        let fileURL = temp.appendingPathComponent("state.json")

        let store = ReminderStateStore(fileURL: fileURL)
        let configuredCodexHome = temp.appendingPathComponent("custom-codex", isDirectory: true)
        store.saveSettings(
            ReminderSettings(
                idleMinutes: 9,
                pollSeconds: 42,
                recencyWindowHours: 7,
                reminderMinutes: 33,
                useRepoRoot: false,
                codexHomePath: configuredCodexHome.path
            )
        )

        let monitor = SessionMonitor(notifier: FakeNotifier(), stateStore: store, autostart: false)
        XCTAssertEqual(monitor.idleMinutes, 9)
        XCTAssertEqual(monitor.pollSeconds, 42)
        XCTAssertEqual(monitor.recencyWindowHours, 7)
        XCTAssertEqual(monitor.reminderMinutes, 33)
        XCTAssertFalse(monitor.useRepoRoot)
        XCTAssertEqual(monitor.codexHomePath, configuredCodexHome.path)
        XCTAssertEqual(
            monitor.resolvedCodexSessionsPath,
            configuredCodexHome.appendingPathComponent("sessions", isDirectory: true).path
        )
    }

    func testAutostartConvenienceInitRunsStartupFlow() async throws {
        let notifier = FakeNotifier()
        let monitor = SessionMonitor(notifier: notifier, autostart: true)
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(notifier.requestPermissionCalls, 0)
        XCTAssertTrue(
            monitor.statusText == "Monitoring CodexTurn sessions"
                || monitor.statusText.contains("No recent projects")
                || monitor.statusText.contains("Tracking")
        )
    }
}
