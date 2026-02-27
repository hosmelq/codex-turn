import Foundation

struct ProjectReminderState: Codable {
    var projectPath: String
    var state: String
    var lastNotifiedAt: Date
    var lastStateFingerprint: String
}

struct ReminderSettings: Codable, Equatable {
    var idleMinutes: TimeInterval
    var pollSeconds: TimeInterval
    var recencyWindowHours: TimeInterval
    var reminderMinutes: TimeInterval
    var useRepoRoot: Bool
    var codexHomePath: String?

    private static let idleMinutesBounds: ClosedRange<TimeInterval> = 1...120
    private static let pollSecondsBounds: ClosedRange<TimeInterval> = 10...600
    private static let recencyWindowHoursBounds: ClosedRange<TimeInterval> = 1...24
    private static let reminderMinutesBounds: ClosedRange<TimeInterval> = 5...120

    static var defaults: ReminderSettings {
        ReminderSettings(
            idleMinutes: AppConstants.defaultIdleMinutes,
            pollSeconds: AppConstants.defaultPollSeconds,
            recencyWindowHours: AppConstants.defaultRecencyWindowHours,
            reminderMinutes: AppConstants.defaultReminderMinutes,
            useRepoRoot: true,
            codexHomePath: nil
        )
    }

    func clampedToSupportedBounds() -> ReminderSettings {
        var updated = self
        updated.idleMinutes = min(
            max(updated.idleMinutes, Self.idleMinutesBounds.lowerBound),
            Self.idleMinutesBounds.upperBound
        )
        updated.pollSeconds = min(
            max(updated.pollSeconds, Self.pollSecondsBounds.lowerBound),
            Self.pollSecondsBounds.upperBound
        )
        updated.recencyWindowHours = min(
            max(updated.recencyWindowHours, Self.recencyWindowHoursBounds.lowerBound),
            Self.recencyWindowHoursBounds.upperBound
        )
        updated.reminderMinutes = min(
            max(updated.reminderMinutes, Self.reminderMinutesBounds.lowerBound),
            Self.reminderMinutesBounds.upperBound
        )
        return updated
    }
}

struct ReminderStorage: Codable {
    var states: [String: ProjectReminderState] = [:]
    var fileCursors: [String: FileScanCursor] = [:]
    var settings: ReminderSettings?
}

final class ReminderStateStore {
    private let fileURL: URL
    private var storage: ReminderStorage

    init(fileURL: URL? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let directory =
            (appSupport ?? FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support"))
            .appendingPathComponent("CodexTurn")

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        self.fileURL = fileURL ?? directory.appendingPathComponent("reminder_state.json")
        self.storage = ReminderStorage()

        load()
    }

    func shouldNotify(projectPath: String, stateFingerprint: String, interval: TimeInterval, now: Date) -> Bool {
        guard let existing = storage.states[projectPath] else {
            return true
        }

        if existing.state != ProjectState.waiting.rawValue {
            return true
        }

        if existing.lastStateFingerprint != stateFingerprint {
            return true
        }

        return now.timeIntervalSince(existing.lastNotifiedAt) >= interval
    }

    func recordNotification(projectPath: String, state: String, stateFingerprint: String, now: Date) {
        storage.states[projectPath] = ProjectReminderState(
            projectPath: projectPath,
            state: state,
            lastNotifiedAt: now,
            lastStateFingerprint: stateFingerprint
        )
        save()
    }

    func clearProject(projectPath: String) {
        storage.states[projectPath] = nil
        save()
    }

    func allFileCursors() -> [String: FileScanCursor] {
        storage.fileCursors
    }

    func updateFileCursors(_ updated: [String: FileScanCursor]) {
        storage.fileCursors = updated
        save()
    }

    func loadSettings() -> ReminderSettings {
        guard let stored = storage.settings else {
            return .defaults
        }

        let normalized = stored.clampedToSupportedBounds()
        if normalized != stored {
            storage.settings = normalized
            save()
        }
        return normalized
    }

    func saveSettings(_ settings: ReminderSettings) {
        let normalized = settings.clampedToSupportedBounds()
        if storage.settings == normalized {
            return
        }
        storage.settings = normalized
        save()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode(ReminderStorage.self, from: data)
        else {
            return
        }

        storage = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(storage) else {
            return
        }
        try? data.write(to: fileURL, options: .atomic)
    }
}
