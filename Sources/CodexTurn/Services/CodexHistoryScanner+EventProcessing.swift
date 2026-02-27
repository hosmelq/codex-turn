import Foundation

extension CodexHistoryScanner {
    func readEvents(
        from stream: FileHandle,
        filePath: String,
        cutoffDate: Date,
        fallbackSessionId: String,
        ignoredPrefixes: [String]
    ) -> Int {
        var buffer = Data()
        let chunk = 4096

        while let line = CodexHistoryScannerSupport.readLine(
            from: stream,
            into: &buffer,
            chunk: chunk
        ) {
            autoreleasepool {
                processLine(
                    line,
                    filePath: filePath,
                    cutoffDate: cutoffDate,
                    fallbackSessionId: fallbackSessionId,
                    ignoredPrefixes: ignoredPrefixes
                )
            }
        }

        return buffer.count
    }

    func processLine(
        _ line: String,
        filePath: String,
        cutoffDate: Date,
        fallbackSessionId: String,
        ignoredPrefixes: [String]
    ) {
        let isSessionMeta = line.contains("\"session_meta\"")
        let isResponseItem = line.contains("\"response_item\"")

        guard isSessionMeta || isResponseItem else {
            return
        }
        if isResponseItem && !isUserOrAssistantRoleLine(line) {
            return
        }
        guard
            let envelope = CodexHistoryScannerSupport.parseEnvelope(
                from: line,
                fallbackSessionId: fallbackSessionId
            ),
            let eventTime = envelope.timestamp
        else {
            return
        }

        switch envelope.type {
        case "session_meta":
            applySessionMeta(
                envelope: envelope,
                filePath: filePath,
                eventTime: eventTime,
                fallbackSessionId: fallbackSessionId,
                ignoredPrefixes: ignoredPrefixes
            )
        case "response_item":
            guard eventTime >= cutoffDate else {
                return
            }
            applyResponseItem(
                envelope: envelope,
                filePath: filePath,
                eventTime: eventTime,
                fallbackSessionId: fallbackSessionId,
                ignoredPrefixes: ignoredPrefixes
            )
        default:
            return
        }
    }

    func applySessionMeta(
        envelope: JsonEnvelope,
        filePath: String,
        eventTime: Date,
        fallbackSessionId: String,
        ignoredPrefixes: [String]
    ) {
        guard let cwd = envelope.cwd else {
            return
        }
        guard !CodexHistoryScannerSupport.shouldIgnore(cwd, ignoredPrefixes: ignoredPrefixes) else {
            return
        }

        let snapshotId = envelope.sessionId ?? fallbackSessionId
        let existing =
            sessionSnapshots[snapshotId]
            ?? SessionSnapshot(
                sessionId: snapshotId,
                cwd: cwd,
                firstSeen: eventTime,
                gitBranch: envelope.gitBranch,
                latestEvent: eventTime,
                latestUserEvent: nil,
                latestAssistantEvent: nil,
                latestUserSummary: nil,
                latestAssistantSummary: nil,
                originator: envelope.originator,
                sessionLogPath: filePath,
                source: envelope.source
            )

        var updated = existing
        updated.cwd = cwd
        updated.firstSeen = min(existing.firstSeen, eventTime)
        if let gitBranch = envelope.gitBranch, !gitBranch.isEmpty {
            updated.gitBranch = gitBranch
        }
        if let originator = envelope.originator, !originator.isEmpty {
            updated.originator = originator
        }
        updated.latestEvent = max(existing.latestEvent, eventTime)
        updated.sessionLogPath = filePath
        if let source = envelope.source, !source.isEmpty {
            updated.source = source
        }
        sessionSnapshots[snapshotId] = updated
    }

    func applyResponseItem(
        envelope: JsonEnvelope,
        filePath: String,
        eventTime: Date,
        fallbackSessionId: String,
        ignoredPrefixes: [String]
    ) {
        guard let role = envelope.role, role == "user" || role == "assistant" else {
            return
        }

        let snapshotId = envelope.sessionId ?? fallbackSessionId
        let recoveredCwd = CodexHistoryScannerSupport.extractEnvironmentCwd(from: envelope.messageText)
        let resolvedCwd: String?
        if let recoveredCwd,
            !CodexHistoryScannerSupport.shouldIgnore(recoveredCwd, ignoredPrefixes: ignoredPrefixes)
        {
            resolvedCwd = recoveredCwd
        } else {
            resolvedCwd = nil
        }

        var existing = sessionSnapshots[snapshotId]
        if existing == nil, let resolvedCwd {
            existing = SessionSnapshot(
                sessionId: snapshotId,
                cwd: resolvedCwd,
                firstSeen: eventTime,
                gitBranch: envelope.gitBranch,
                latestEvent: eventTime,
                latestUserEvent: nil,
                latestAssistantEvent: nil,
                latestUserSummary: nil,
                latestAssistantSummary: nil,
                originator: envelope.originator,
                sessionLogPath: filePath,
                source: envelope.source
            )
        }

        guard let existing else {
            return
        }

        var updated = existing
        if let resolvedCwd,
            updated.cwd == "/" || CodexHistoryScannerSupport.shouldIgnore(updated.cwd, ignoredPrefixes: ignoredPrefixes)
        {
            updated.cwd = resolvedCwd
        }
        if let gitBranch = envelope.gitBranch, !gitBranch.isEmpty {
            updated.gitBranch = gitBranch
        }
        if let originator = envelope.originator, !originator.isEmpty {
            updated.originator = originator
        }
        updated.latestEvent = max(updated.latestEvent, eventTime)
        updated.sessionLogPath = filePath
        if let source = envelope.source, !source.isEmpty {
            updated.source = source
        }

        if role == "user" {
            updated.latestUserEvent = CodexHistoryScannerSupport.maxDate(updated.latestUserEvent, eventTime)
        } else {
            updated.latestAssistantEvent = CodexHistoryScannerSupport.maxDate(
                updated.latestAssistantEvent,
                eventTime
            )
        }
        if role == "user",
            let summary = CodexHistoryScannerSupport.summarizeMessage(envelope.messageText)
        {
            updated.latestUserSummary = summary
        }
        if role == "assistant",
            let summary = CodexHistoryScannerSupport.summarizeMessage(envelope.messageText)
        {
            updated.latestAssistantSummary = summary
        }

        sessionSnapshots[snapshotId] = updated
    }

    private func isUserOrAssistantRoleLine(_ line: String) -> Bool {
        line.contains("\"role\":\"assistant\"")
            || line.contains("\"role\":\"user\"")
            || line.contains("\"role\": \"assistant\"")
            || line.contains("\"role\": \"user\"")
    }
}
