import Foundation

extension SessionMonitor {
    public func sessionBadgeText(_ session: SessionSnapshot) -> String {
        switch resolvedTurn(for: session) {
        case .yourTurn(let overdue):
            return overdue ? "overdue" : "your turn"
        case .assistantTurn:
            return "assistant turn"
        case .dormant:
            return "dormant"
        }
    }

    public func sessionStatusIconName(_ session: SessionSnapshot) -> String {
        switch resolvedTurn(for: session) {
        case .yourTurn(let overdue):
            return overdue ? "clock.badge.exclamationmark" : "person.fill"
        case .assistantTurn:
            return "ellipsis.bubble.fill"
        case .dormant:
            return "moon.zzz.fill"
        }
    }

    public func sessionTimeText(_ session: SessionSnapshot) -> String {
        switch resolvedTurn(for: session) {
        case .yourTurn, .assistantTurn:
            return turnElapsedText(for: session)
        case .dormant:
            return session.latestEvent.timeAgoDisplay()
        }
    }

    public func sessionIsWaiting(_ session: SessionSnapshot) -> Bool {
        if case .yourTurn(let overdue) = resolvedTurn(for: session) {
            return overdue
        }
        return false
    }

    public func sessionContextLine(_ session: SessionSnapshot) -> String {
        var parts: [String] = []

        if let branch = normalizedPart(session.gitBranch) {
            parts.append(branch)
        }
        if let originatorSource = originatorSourceText(session: session) {
            parts.append(originatorSource)
        }
        parts.append(sessionTimeText(session))

        return parts.joined(separator: " • ")
    }

    private func resolvedTurn(for session: SessionSnapshot) -> SessionTurnResolver.ConversationTurn {
        SessionTurnResolver.sessionTurn(
            session: session,
            now: Date(),
            idleMinutes: idleMinutes
        )
    }

    private func turnElapsedText(for session: SessionSnapshot) -> String {
        SessionTurnResolver.sessionTurnElapsed(session: session).waitingDurationDisplay()
    }

    private func normalizedPart(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func originatorSourceText(session: SessionSnapshot) -> String? {
        let normalizedSource = normalizedPart(session.source)?.lowercased()

        if let appName = appNameHint(from: session.cwd) {
            return normalizedSource == "cli" ? cliLabel(from: appName) : appName
        }

        if let family = producerFamily(from: normalizedPart(session.originator)) {
            return normalizedSource == "cli" ? cliLabel(from: family) : family
        }

        if normalizedSource == "vscode" {
            return "VS Code"
        }
        if normalizedSource == "cli" {
            return "CLI"
        }

        return nil
    }

    private func producerFamily(from originator: String?) -> String? {
        guard let originator else {
            return nil
        }

        let components = originator.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        guard !components.isEmpty else {
            return originator
        }

        let ignoredParts = Set(["cli", "exec", "desktop", "sdk", "rs", "ts", "js", "py", "go", "vscode"])
        let filtered =
            components
            .map(String.init)
            .filter { !ignoredParts.contains($0.lowercased()) }

        if filtered.isEmpty {
            return nil
        }

        return filtered.prefix(2).map(displayToken(from:)).joined(separator: " ")
    }

    private func appNameHint(from cwd: String?) -> String? {
        guard let cwd = normalizedPart(cwd) else {
            return nil
        }

        let lowercasedCwd = cwd.lowercased()
        if lowercasedCwd.contains("/.local/share/opencode/")
            || lowercasedCwd.contains("/.opencode/")
        {
            return "Opencode"
        }

        let pathComponents = (cwd as NSString).pathComponents
        if pathComponents.count > 1 {
            for index in 0..<(pathComponents.count - 1) {
                let current = pathComponents[index]
                let next = pathComponents[index + 1].lowercased()
                guard current.hasPrefix("."), current.count > 1, next == "clones" else {
                    continue
                }
                let hostToken = String(current.dropFirst())
                return
                    hostToken
                    .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    .map { displayToken(from: String($0)) }
                    .joined(separator: " ")
            }
        }

        return nil
    }

    private func displayToken(from value: String) -> String {
        guard !value.isEmpty else {
            return value
        }

        if value.count <= 3 {
            return value.uppercased()
        }

        return value.prefix(1).uppercased() + value.dropFirst().lowercased()
    }

    private func cliLabel(from value: String) -> String {
        if value.localizedCaseInsensitiveContains("cli") {
            return value
        }
        return "\(value) CLI"
    }
}
