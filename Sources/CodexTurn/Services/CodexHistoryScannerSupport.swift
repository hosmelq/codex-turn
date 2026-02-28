import Foundation

struct JsonEnvelope {
    let type: String
    let timestamp: Date?
    let sessionId: String?
    let cwd: String?
    let gitBranch: String?
    let originator: String?
    let role: String?
    let messageText: String?
    let source: String?
}

enum CodexHistoryScannerSupport {
    private static let fallbackIsoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func deriveSessionId(from fileName: String) -> String {
        let stem = (fileName as NSString).deletingPathExtension

        let components = stem.split(separator: "-")
        if components.count >= 5 {
            let tail = Array(components.suffix(5))
            let uuidPartLengths = [8, 4, 4, 4, 12]

            let looksLikeUUID = zip(tail, uuidPartLengths).allSatisfy { part, expectedLength in
                part.count == expectedLength
                    && part.unicodeScalars.allSatisfy { scalar in
                        switch scalar.value {
                        case 48...57, 65...70, 97...102:
                            return true
                        default:
                            return false
                        }
                    }
            }

            if looksLikeUUID {
                return tail.map(String.init).joined(separator: "-")
            }
        }

        return stem
    }

    static func extractMessageText(from content: Any?) -> String? {
        guard let items = content as? [[String: Any]], !items.isEmpty else {
            return nil
        }

        for item in items {
            if let text = item["text"] as? String,
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return text
            }
        }

        return nil
    }

    static func maxDate(_ current: Date?, _ candidate: Date) -> Date {
        guard let current else {
            return candidate
        }
        return max(current, candidate)
    }

    static func openFile(forReading fileURL: URL) -> FileHandle? {
        try? FileHandle(forReadingFrom: fileURL)
    }

    static func parseDate(_ value: String) -> Date? {
        if let date = isoFormatter.date(from: value) {
            return date
        }
        if let date = fallbackIsoFormatter.date(from: value) {
            return date
        }
        return nil
    }

    static func parseEnvelope(from line: String, fallbackSessionId: String) -> JsonEnvelope? {
        guard let data = line.data(using: .utf8),
            let raw = try? JSONSerialization.jsonObject(with: data),
            let dict = raw as? [String: Any],
            let type = dict["type"] as? String
        else {
            return nil
        }

        let payload = (dict["payload"] as? [String: Any]) ?? [:]
        let payloadItem = payload["item"] as? [String: Any]

        var timestamp: Date?
        if let isoTimestamp = dict["timestamp"] as? String {
            timestamp = parseDate(isoTimestamp)
        } else if let isoTimestamp = payload["timestamp"] as? String {
            timestamp = parseDate(isoTimestamp)
        }

        let sessionId: String
        if type == "session_meta" {
            sessionId =
                (dict["session_id"] as? String)
                ?? (payload["session_id"] as? String)
                ?? (payload["id"] as? String)
                ?? fallbackSessionId
        } else {
            sessionId =
                (dict["session_id"] as? String)
                ?? (payload["session_id"] as? String)
                ?? fallbackSessionId
        }

        let baseInstructionsText =
            (payload["base_instructions"] as? [String: Any])?["text"] as? String
            ?? (payload["base_instructions"] as? String)
        var cwd = payload["cwd"] as? String
        if let extractedWorkspaceRoot = extractWorkspaceRoot(from: baseInstructionsText),
            cwd == nil || cwd == "/" || cwd?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
        {
            cwd = extractedWorkspaceRoot
        }
        let gitBranch = (payload["git"] as? [String: Any])?["branch"] as? String
        let originator = payload["originator"] as? String
        let role = (payload["role"] as? String) ?? (payloadItem?["role"] as? String)
        let source = payload["source"] as? String

        let messageText: String?
        if type == "response_item" {
            messageText =
                extractMessageText(from: payload["content"])
                ?? extractMessageText(from: payloadItem?["content"])
                ?? (payload["text"] as? String)
                ?? (payloadItem?["text"] as? String)
        } else {
            messageText = nil
        }

        return JsonEnvelope(
            type: type,
            timestamp: timestamp,
            sessionId: sessionId,
            cwd: cwd,
            gitBranch: gitBranch,
            originator: originator,
            role: role,
            messageText: messageText,
            source: source
        )
    }

    static func readLine(
        from fileHandle: FileHandle,
        into buffer: inout Data,
        chunk: Int
    ) -> String? {
        while true {
            if let range = buffer.range(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: 0..<range.lowerBound)
                buffer.removeSubrange(0...range.lowerBound)
                return String(data: lineData, encoding: .utf8)
            }

            let newData = fileHandle.readData(ofLength: chunk)
            if newData.isEmpty {
                return nil
            }

            buffer.append(newData)
        }
    }

    static func shouldIgnore(_ path: String, ignoredPrefixes: [String]) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardized.path
        if standardized == "/" || standardized.isEmpty {
            return true
        }
        return ignoredPrefixes.contains { prefix in standardized.hasPrefix(prefix) }
    }

    static func summarizeMessage(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let collapsedWhitespace =
            text
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

        let endIndex = collapsedWhitespace.index(collapsedWhitespace.startIndex, offsetBy: maxLength)
        let truncated = collapsedWhitespace[..<endIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(truncated)..."
    }

    static func extractEnvironmentCwd(from text: String?) -> String? {
        guard let text else {
            return nil
        }

        if let contextRange = standaloneEnvironmentContextRange(in: text),
            let cwd = extractCwdValue(in: text, within: contextRange),
            isLikelyFilesystemPath(cwd)
        {
            return URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath).standardized.path
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isStandaloneTag(trimmed, tag: "cwd"),
            let cwd = extractCwdValue(in: trimmed, within: trimmed.startIndex..<trimmed.endIndex),
            isLikelyFilesystemPath(cwd)
        {
            return URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath).standardized.path
        }

        return nil
    }

    private static func standaloneEnvironmentContextRange(in text: String) -> Range<String.Index>? {
        guard let start = text.range(of: "<environment_context>"),
            let end = text.range(of: "</environment_context>", range: start.upperBound..<text.endIndex)
        else {
            return nil
        }

        let leadingText = text[..<start.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingText = text[end.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard leadingText.isEmpty, trailingText.isEmpty else {
            return nil
        }

        return start.upperBound..<end.lowerBound
    }

    private static func isStandaloneTag(_ text: String, tag: String) -> Bool {
        let opening = "<\(tag)>"
        let closing = "</\(tag)>"
        return text.hasPrefix(opening) && text.hasSuffix(closing)
    }

    private static func extractCwdValue(in text: String, within range: Range<String.Index>) -> String? {
        guard let cwdStartRange = text.range(of: "<cwd>", range: range),
            let cwdEndRange = text.range(
                of: "</cwd>",
                range: cwdStartRange.upperBound..<range.upperBound
            )
        else {
            return nil
        }

        let extracted = text[cwdStartRange.upperBound..<cwdEndRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return extracted.isEmpty ? nil : extracted
    }

    private static func isLikelyFilesystemPath(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return false
        }

        let hasForbiddenMarkers =
            trimmed.contains("<") || trimmed.contains(">") || trimmed.contains("\n")
            || trimmed.contains("\r")
        if hasForbiddenMarkers {
            return false
        }

        return trimmed.hasPrefix("/") || trimmed == "~" || trimmed.hasPrefix("~/")
    }

    private static func extractWorkspaceRoot(from text: String?) -> String? {
        guard let text else {
            return nil
        }

        let markers = [
            "Workspace root: `",
            "Workspace root: \"",
            "Workspace root: '",
        ]

        for marker in markers {
            guard let markerRange = text.range(of: marker) else {
                continue
            }

            let suffix = text[markerRange.upperBound...]
            let delimiter = String(marker.last ?? "`")

            if let closingIndex = suffix.firstIndex(of: Character(delimiter)) {
                let value = suffix[..<closingIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return (value as NSString).expandingTildeInPath
                }
            }
        }

        return nil
    }
}
