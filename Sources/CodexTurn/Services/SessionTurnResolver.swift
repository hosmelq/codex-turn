import Foundation

enum SessionTurnResolver {
    enum ConversationTurn {
        case assistantTurn
        case dormant
        case yourTurn(overdue: Bool)
    }

    static func projectSortPriority(
        project: ProjectGroup,
        now: Date,
        idleMinutes: TimeInterval
    ) -> Int {
        guard let latest = project.latestSession else {
            return 3
        }
        switch sessionTurn(session: latest, now: now, idleMinutes: idleMinutes) {
        case .yourTurn(let overdue):
            return overdue ? 0 : 1
        case .assistantTurn:
            return 2
        case .dormant:
            return 3
        }
    }

    static func sessionTurn(
        session: SessionSnapshot,
        now: Date,
        idleMinutes: TimeInterval
    ) -> ConversationTurn {
        let threshold = idleMinutes * 60

        switch (session.latestUserEvent, session.latestAssistantEvent) {
        case (nil, nil):
            return .dormant
        case (.none, .some(let assistantDate)):
            let overdue = now.timeIntervalSince(assistantDate) >= threshold
            return .yourTurn(overdue: overdue)
        case (.some, .none):
            return .assistantTurn
        case (.some(let userDate), .some(let assistantDate)):
            if assistantDate >= userDate {
                let overdue = now.timeIntervalSince(assistantDate) >= threshold
                return .yourTurn(overdue: overdue)
            }
            return .assistantTurn
        }
    }

    static func sessionTurnElapsed(session: SessionSnapshot) -> Date {
        switch (session.latestUserEvent, session.latestAssistantEvent) {
        case (.none, .some(let assistantDate)):
            return assistantDate
        case (.some(let userDate), .none):
            return userDate
        case (.some(let userDate), .some(let assistantDate)):
            return assistantDate >= userDate ? assistantDate : userDate
        default:
            return session.latestEvent
        }
    }
}
