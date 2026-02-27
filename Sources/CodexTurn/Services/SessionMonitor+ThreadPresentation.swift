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
        let originator = normalizedPart(session.originator)
        let source = normalizedPart(session.source)

        switch (originator, source) {
        case (.some(let originator), .some(let source)):
            return "\(originator)(\(source))"
        case (.some(let originator), .none):
            return originator
        case (.none, .some(let source)):
            return source
        case (.none, .none):
            return nil
        }
    }
}
