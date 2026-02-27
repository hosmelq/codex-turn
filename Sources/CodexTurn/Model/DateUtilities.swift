import Foundation

extension Date {
    func timeAgoDisplay(now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(self))
        if seconds < 60 {
            return "just now"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }

        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h ago"
        }

        let days = hours / 24
        return "\(days)d ago"
    }

    func waitingDurationDisplay(now: Date = Date()) -> String {
        guard now >= self else { return "0m" }
        let minutes = Int(now.timeIntervalSince(self) / 60)
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h"
        }
        let days = hours / 24
        return "\(days)d"
    }
}

func stateFingerprint(_ waitingSince: Date?, _ latestEvent: Date) -> String {
    guard let waitingSince else { return "active-\(latestEvent.timeIntervalSinceReferenceDate)" }
    return "waiting-\(Int(waitingSince.timeIntervalSinceReferenceDate))"
}
