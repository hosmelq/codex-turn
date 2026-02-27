import Foundation

@MainActor
public final class SessionMonitor: ObservableObject {
    @Published public var projects: [ProjectGroup] = []
    @Published public var statusText: String = "Monitoring CodexTurn sessions"
    @Published public var hasPermission: Bool = false
    @Published public var useRepoRoot: Bool = true {
        didSet {
            handleSettingsDidChange(.refresh)
        }
    }
    @Published public var recencyWindowHours: TimeInterval = AppConstants.defaultRecencyWindowHours {
        didSet {
            handleSettingsDidChange(.refresh)
        }
    }
    @Published public var idleMinutes: TimeInterval = AppConstants.defaultIdleMinutes {
        didSet {
            handleSettingsDidChange(.refresh)
        }
    }
    @Published public var reminderMinutes: TimeInterval = AppConstants.defaultReminderMinutes {
        didSet {
            handleSettingsDidChange(.refresh)
        }
    }
    @Published public var pollSeconds: TimeInterval = AppConstants.defaultPollSeconds {
        didSet {
            handleSettingsDidChange(.restartPolling)
        }
    }
    @Published public var codexHomePath: String = "" {
        didSet {
            handleSettingsDidChange(.refresh)
        }
    }

    public var resolvedCodexSessionsPath: String {
        Self.resolvedCodexSessionsDirectory(for: codexHomePath).path
    }

    private let notifier: ProjectNotifying
    private let refreshScheduler = RefreshScheduler()
    private let scanWorker: SessionScanWorker
    private let stateStore: ReminderStateStore
    private let managesScannerDirectory: Bool
    private var isRefreshing = false
    private var isRestoringSettings = false

    private enum SettingsChangeEffect {
        case refresh
        case restartPolling
    }

    init(
        notifier: any ProjectNotifying,
        stateStore: ReminderStateStore = ReminderStateStore(),
        scanner: CodexHistoryScanner? = nil,
        autostart: Bool = true
    ) {
        self.notifier = notifier
        self.stateStore = stateStore
        let persistedSettings = stateStore.loadSettings()
        let configuredCodexHomePath = persistedSettings.codexHomePath ?? ""
        isRestoringSettings = true
        useRepoRoot = persistedSettings.useRepoRoot
        recencyWindowHours = persistedSettings.recencyWindowHours
        idleMinutes = persistedSettings.idleMinutes
        reminderMinutes = persistedSettings.reminderMinutes
        pollSeconds = persistedSettings.pollSeconds
        codexHomePath = configuredCodexHomePath
        isRestoringSettings = false

        if let scanner {
            self.managesScannerDirectory = false
            self.scanWorker = SessionScanWorker(scanner: scanner)
        } else {
            let scannerInstance = CodexHistoryScanner(
                initialFileCursors: stateStore.allFileCursors(),
                sessionsDirectory: Self.resolvedCodexSessionsDirectory(for: configuredCodexHomePath)
            )
            self.managesScannerDirectory = true
            self.scanWorker = SessionScanWorker(scanner: scannerInstance)
        }
        statusText = "Monitoring CodexTurn sessions"
        if autostart {
            startPolling()
        }
    }

    public convenience init(notifier: any ProjectNotifying, autostart: Bool = true) {
        self.init(
            notifier: notifier,
            stateStore: ReminderStateStore(),
            scanner: nil,
            autostart: autostart
        )
    }

    public func requestNotificationPermission() async {
        do {
            try await notifier.requestPermission()
            hasPermission = true
            statusText = "Notifications enabled"

            do {
                try await notifier.notify(
                    title: "CodexTurn",
                    body: "Notifications are enabled."
                )
            } catch {
                statusText = "Notifications enabled (delivery check failed)"
            }
        } catch {
            hasPermission = false
            statusText = "Notification permission required"
        }
    }

    public func sendTestNotification() async {
        do {
            try await notifier.requestPermission()
            hasPermission = true
            try await notifier.notify(
                title: "CodexTurn",
                body: "Test notification delivered successfully."
            )
            statusText = "Sent test notification"
        } catch {
            hasPermission = false
            statusText = "Notification permission required"
            notifier.openSystemNotificationSettings()
        }
    }

    public func openSystemNotificationSettings() {
        notifier.openSystemNotificationSettings()
    }

    public func refresh() async {
        guard !isRefreshing else {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()
        let cutoff = now.addingTimeInterval(-recencyWindowHours * 3600)

        if managesScannerDirectory {
            let sessionsDirectory = Self.resolvedCodexSessionsDirectory(for: codexHomePath)
            let didChangeSessionsDirectory = await scanWorker.setSessionsDirectory(sessionsDirectory)
            if didChangeSessionsDirectory {
                stateStore.updateFileCursors([:])
            }
        }

        let scan = await scanWorker.scan(
            by: cutoff,
            useRepoRoot: useRepoRoot,
            ignoredPrefixes: Self.resolvedIgnoredPrefixes(for: codexHomePath)
        )

        stateStore.updateFileCursors(scan.fileCursors)

        let grouped = scan.result.projectGroups.values
            .filter { !$0.projectPath.isEmpty }
            .filter { !$0.sessions.isEmpty }
            .sorted {
                let lhsPriority = SessionTurnResolver.projectSortPriority(
                    project: $0,
                    now: now,
                    idleMinutes: idleMinutes
                )
                let rhsPriority = SessionTurnResolver.projectSortPriority(
                    project: $1,
                    now: now,
                    idleMinutes: idleMinutes
                )
                if lhsPriority == rhsPriority {
                    return $0.lastSeen > $1.lastSeen
                }
                return lhsPriority < rhsPriority
            }

        self.projects = grouped
        statusText =
            grouped.isEmpty
            ? "No recent projects in last \(Int(recencyWindowHours))h"
            : "Tracking \(grouped.count) project(s)"

        for project in grouped {
            await evaluate(project: project, now: now)
        }
    }

    public func evaluate(project: ProjectGroup, now: Date) async {
        guard let latest = project.latestSession else {
            stateStore.clearProject(projectPath: project.projectPath)
            return
        }

        guard
            case .yourTurn(let overdue) = SessionTurnResolver.sessionTurn(
                session: latest,
                now: now,
                idleMinutes: idleMinutes
            ),
            overdue
        else {
            stateStore.clearProject(projectPath: project.projectPath)
            return
        }
        let waitingSince = latest.latestAssistantEvent ?? latest.latestEvent

        let fingerprint = stateFingerprint(waitingSince, latest.latestEvent)
        if stateStore.shouldNotify(
            projectPath: project.projectPath,
            stateFingerprint: fingerprint,
            interval: reminderMinutes * 60,
            now: now
        ) {
            let waitingDuration = waitingSince.waitingDurationDisplay(now: now)
            do {
                try await notifier.notify(
                    title: "\(project.displayName) is waiting on you",
                    body: "Your reply is overdue by \(waitingDuration)."
                )
                stateStore.recordNotification(
                    projectPath: project.projectPath,
                    state: ProjectState.waiting.rawValue,
                    stateFingerprint: fingerprint,
                    now: now
                )
            } catch {
                statusText = "Notification permission required"
                hasPermission = false
            }
        }
    }

    public func startPolling() {
        refreshScheduler.configure(interval: max(5, pollSeconds)) { [weak self] in
            guard let self else {
                return
            }
            Task { [weak self] in
                guard let self else {
                    return
                }
                await self.refresh()
            }
        }
    }
}

extension SessionMonitor {
    public func projectStateText(_ project: ProjectGroup) -> String {
        guard let latest = project.latestSession else {
            return "Dormant"
        }

        switch SessionTurnResolver.sessionTurn(
            session: latest,
            now: Date(),
            idleMinutes: idleMinutes
        ) {
        case .yourTurn(let overdue):
            let elapsed = SessionTurnResolver.sessionTurnElapsed(session: latest).waitingDurationDisplay()
            return overdue ? "Your turn • overdue \(elapsed)" : "Your turn • \(elapsed)"
        case .assistantTurn:
            let elapsed = SessionTurnResolver.sessionTurnElapsed(session: latest).waitingDurationDisplay()
            return "Assistant turn • \(elapsed)"
        case .dormant:
            return "Dormant"
        }
    }

    public func sessions(for project: ProjectGroup) -> [SessionSnapshot] {
        project.sessions.sorted { $0.latestEvent > $1.latestEvent }
    }

    public func sessionTitle(_ session: SessionSnapshot) -> String {
        if let summary = latestSummary(for: session) {
            return summary
        }

        let tail = session.sessionId.count > 8 ? String(session.sessionId.suffix(8)) : session.sessionId
        return "Thread \(tail)"
    }

    public func projectLastActiveText(_ project: ProjectGroup) -> String {
        project.latestSession?.latestEvent.timeAgoDisplay() ?? "unknown"
    }

    private func latestSummary(for session: SessionSnapshot) -> String? {
        let userSummary = normalizedSummary(session.latestUserSummary)
        let assistantSummary = normalizedSummary(session.latestAssistantSummary)

        switch (session.latestUserEvent, session.latestAssistantEvent) {
        case (.some, .none):
            return userSummary ?? assistantSummary
        case (.none, .some):
            return assistantSummary ?? userSummary
        case (.some(let userDate), .some(let assistantDate)):
            if assistantDate >= userDate {
                return assistantSummary ?? userSummary
            }
            return userSummary ?? assistantSummary
        case (.none, .none):
            return userSummary ?? assistantSummary
        }
    }

    private func normalizedSummary(_ summary: String?) -> String? {
        guard let summary else {
            return nil
        }
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedCodexHomePath(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return (trimmed as NSString).expandingTildeInPath
    }

    private static func resolvedCodexHomeDirectory(for configuredPath: String) -> URL {
        if let normalized = normalizedCodexHomePath(configuredPath) {
            return URL(fileURLWithPath: normalized, isDirectory: true)
        }

        return AppConstants.codexHomeDirectory
    }

    private static func resolvedCodexSessionsDirectory(for configuredPath: String) -> URL {
        resolvedCodexHomeDirectory(for: configuredPath)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    private static func resolvedIgnoredPrefixes(for configuredPath: String) -> [String] {
        let memoriesPath = resolvedCodexHomeDirectory(for: configuredPath)
            .appendingPathComponent("memories", isDirectory: true)
            .standardizedFileURL.path
        return Array(Set(AppConstants.ignorePathPrefixes + [memoriesPath]))
    }

    private func handleSettingsDidChange(_ effect: SettingsChangeEffect) {
        persistSettings()
        switch effect {
        case .refresh:
            refreshAfterSettingsChange()
        case .restartPolling:
            restartPollingAfterSettingsChange()
        }
    }

    private func persistSettings() {
        guard !isRestoringSettings else {
            return
        }
        stateStore.saveSettings(
            ReminderSettings(
                idleMinutes: idleMinutes,
                pollSeconds: pollSeconds,
                recencyWindowHours: recencyWindowHours,
                reminderMinutes: reminderMinutes,
                useRepoRoot: useRepoRoot,
                codexHomePath: Self.normalizedCodexHomePath(codexHomePath)
            )
        )
    }

    private func refreshAfterSettingsChange() {
        guard !isRestoringSettings else {
            return
        }
        Task { [weak self] in
            guard let self else { return }
            await self.refresh()
        }
    }

    private func restartPollingAfterSettingsChange() {
        guard !isRestoringSettings else {
            return
        }
        startPolling()
    }
}
