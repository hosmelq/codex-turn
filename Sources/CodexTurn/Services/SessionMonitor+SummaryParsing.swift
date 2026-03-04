import Foundation

extension SessionMonitor {
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
        guard !trimmed.isEmpty else {
            return nil
        }

        if let firstCharacter = trimmed.first, firstCharacter == "{" || firstCharacter == "[" {
            if let extracted = extractSummaryFromStructuredText(trimmed) {
                return extracted
            }
            if looksLikeStructuredPayload(trimmed) {
                return nil
            }
            return trimmed
        }

        return trimmed
    }

    private func extractSummaryFromStructuredText(_ text: String) -> String? {
        guard let firstCharacter = text.first, firstCharacter == "{" || firstCharacter == "[" else {
            return nil
        }

        guard
            let data = text.data(using: .utf8),
            let parsed = try? JSONSerialization.jsonObject(with: data)
        else {
            return regexSummaryCandidate(in: text)
        }

        return structuredSummaryCandidate(from: parsed) ?? regexSummaryCandidate(in: text)
    }

    private func structuredSummaryCandidate(from value: Any) -> String? {
        switch value {
        case let text as String:
            return cleanSummaryValue(text)
        case let array as [Any]:
            for entry in array {
                if let candidate = structuredSummaryCandidate(from: entry) {
                    return candidate
                }
            }
            return nil
        case let dictionary as [String: Any]:
            if let findings = dictionary["findings"] as? [Any] {
                for finding in findings {
                    if let candidate = structuredSummaryCandidate(from: finding) {
                        return candidate
                    }
                }
            }

            let preferredKeys = ["title", "summary", "message", "text", "description", "overall_explanation"]
            for key in preferredKeys {
                if let candidate = cleanSummaryValue(dictionary[key] as? String) {
                    return candidate
                }
            }

            let nestedKeys = ["result", "data", "output", "content", "items"]
            for key in nestedKeys {
                if let nested = dictionary[key],
                    let candidate = structuredSummaryCandidate(from: nested)
                {
                    return candidate
                }
            }

            return nil
        default:
            return nil
        }
    }

    private func cleanSummaryValue(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let collapsedWhitespace =
            value
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsedWhitespace.isEmpty else {
            return nil
        }

        let maxLength = 72
        if collapsedWhitespace.count <= maxLength {
            return collapsedWhitespace
        }

        let endIndex = collapsedWhitespace.index(
            collapsedWhitespace.startIndex,
            offsetBy: maxLength
        )
        let truncated = collapsedWhitespace[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(truncated)..."
    }

    private func regexSummaryCandidate(in text: String) -> String? {
        let pattern =
            #""(?:title|summary|message|text|description|overall_explanation)"\s*:\s*"((?:\\.|[^"\\])*)(?:"|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
            match.numberOfRanges > 1,
            let capturedRange = Range(match.range(at: 1), in: text)
        else {
            return nil
        }

        return cleanSummaryValue(unescapeJSONString(text[capturedRange]))
    }

    private func looksLikeStructuredPayload(_ text: String) -> Bool {
        guard let firstCharacter = text.first else {
            return false
        }

        if firstCharacter == "{" {
            return true
        }
        guard firstCharacter == "[" else {
            return false
        }

        let afterBracket = text.dropFirst().drop(while: \.isWhitespace)
        guard let nextCharacter = afterBracket.first else {
            return false
        }

        if nextCharacter == "{" || nextCharacter == "[" || nextCharacter == "\"" {
            return true
        }
        if nextCharacter.isNumber || nextCharacter == "-" {
            return true
        }

        return false
    }

    private func unescapeJSONString(_ value: Substring) -> String {
        String(value)
            .replacingOccurrences(of: #"\\n"#, with: " ")
            .replacingOccurrences(of: #"\\r"#, with: " ")
            .replacingOccurrences(of: #"\\t"#, with: " ")
            .replacingOccurrences(of: #"\""#, with: "\"")
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\\\"#, with: "\\")
    }
}
