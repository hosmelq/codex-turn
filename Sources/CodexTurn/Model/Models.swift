import Foundation

struct AppConstants {
    static var codexHomeDirectory: URL {
        resolveCodexHomeDirectory(homeDirectory: NSHomeDirectory())
    }

    static var codexSessionsDirectory: URL {
        codexHomeDirectory.appendingPathComponent("sessions", isDirectory: true)
    }

    static let defaultRecencyWindowHours: TimeInterval = 4
    static let defaultIdleMinutes: TimeInterval = 20
    static let defaultReminderMinutes: TimeInterval = 30
    static let defaultPollSeconds: TimeInterval = 60
    static let maxScanTailBytes: UInt64 = 2 * 1024 * 1024
    static let snapshotRetentionHours: TimeInterval = 48

    static let ignorePathPrefixes: [String] = [
        NSHomeDirectory().appending("/Library/Caches"),
        NSHomeDirectory().appending("/Library/Logs"),
        "/private/var/folders",
        "/tmp",
    ]

    static let sessionFileExtensions = Set(["jsonl"])

    static func resolveCodexHomeDirectory(homeDirectory: String) -> URL {
        URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .appendingPathComponent(".codex", isDirectory: true)
    }
}

struct FileScanCursor: Codable, Equatable {
    var offset: UInt64
    var fileSize: UInt64
    var modifiedAt: Date?
}

public struct ProjectGroup: Identifiable, Equatable, Codable {
    public var id: String
    public var displayName: String
    public var projectPath: String
    public var sessions: [SessionSnapshot]

    var latestSession: SessionSnapshot? {
        sessions.max(by: { $0.latestEvent < $1.latestEvent })
    }

    public var state: ProjectState {
        latestSession?.state ?? .idle
    }

    var lastSeen: Date {
        latestSession?.latestEvent ?? .distantPast
    }
}

public struct SessionSnapshot: Codable, Equatable {
    public var sessionId: String
    public var cwd: String
    public var firstSeen: Date
    public var gitBranch: String?
    public var latestEvent: Date
    public var latestUserEvent: Date?
    public var latestAssistantEvent: Date?
    public var latestUserSummary: String?
    public var latestAssistantSummary: String?
    public var originator: String?
    public var sessionLogPath: String?
    public var source: String?

    public init(
        sessionId: String,
        cwd: String,
        firstSeen: Date,
        gitBranch: String? = nil,
        latestEvent: Date,
        latestUserEvent: Date?,
        latestAssistantEvent: Date?,
        latestUserSummary: String?,
        latestAssistantSummary: String? = nil,
        originator: String? = nil,
        sessionLogPath: String? = nil,
        source: String? = nil
    ) {
        self.sessionId = sessionId
        self.cwd = cwd
        self.firstSeen = firstSeen
        self.gitBranch = gitBranch
        self.latestEvent = latestEvent
        self.latestUserEvent = latestUserEvent
        self.latestAssistantEvent = latestAssistantEvent
        self.latestUserSummary = latestUserSummary
        self.latestAssistantSummary = latestAssistantSummary
        self.originator = originator
        self.sessionLogPath = sessionLogPath
        self.source = source
    }

    public var waitingSeconds: TimeInterval? {
        guard let latestUserEvent else { return nil }
        if let latestAssistantEvent, latestAssistantEvent >= latestUserEvent {
            return nil
        }
        return Date().timeIntervalSince(latestUserEvent)
    }

    public var state: ProjectState {
        guard let latestUserEvent else {
            return .active
        }

        if let latestAssistantEvent, latestAssistantEvent >= latestUserEvent {
            return .active
        }

        return .waiting
    }
}

public enum ProjectState: String, Codable, CaseIterable {
    case waiting
    case active
    case idle
}

struct ScanResult {
    let projectGroups: [String: ProjectGroup]
    let totalSessions: Int
}
