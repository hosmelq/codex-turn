import Foundation

protocol CodexHistoryScanning {
    func scanRecentSessions(
        by cutoffDate: Date,
        useRepoRoot: Bool,
        ignoredPrefixes: [String]
    ) -> ScanResult
}

final class CodexHistoryScanner: CodexHistoryScanning {
    var fileCursors: [String: FileScanCursor]
    var sessionSnapshots: [String: SessionSnapshot] = [:]
    private(set) var sessionsDirectory: URL

    init(
        initialFileCursors: [String: FileScanCursor] = [:],
        sessionsDirectory: URL = AppConstants.codexSessionsDirectory
    ) {
        self.fileCursors = initialFileCursors
        self.sessionsDirectory = sessionsDirectory.standardizedFileURL
    }

    @discardableResult
    func setSessionsDirectory(_ directory: URL) -> Bool {
        let normalized = directory.standardizedFileURL
        guard normalized.path != sessionsDirectory.path else {
            return false
        }

        sessionsDirectory = normalized
        fileCursors.removeAll()
        sessionSnapshots.removeAll()
        return true
    }

    func currentFileCursors() -> [String: FileScanCursor] {
        fileCursors
    }

    func scanRecentSessions(
        by cutoffDate: Date,
        useRepoRoot: Bool,
        ignoredPrefixes: [String] = AppConstants.ignorePathPrefixes
    ) -> ScanResult {
        var discoveredFilePaths = Set<String>()
        let candidates = candidateSessionFiles(cutoffDate: cutoffDate)
        for fileURL in candidates {

            discoveredFilePaths.insert(fileURL.path)
            processFile(
                at: fileURL,
                cutoffDate: cutoffDate,
                ignoredPrefixes: ignoredPrefixes
            )
        }

        cleanupStaleFileCursors(keeping: discoveredFilePaths)
        cleanupOrphanSnapshots(keeping: discoveredFilePaths)
        cleanupStaleSnapshots(cutoffDate: cutoffDate)

        let recentSessions = sessionSnapshots.values.filter { $0.latestEvent >= cutoffDate }
        let groups = buildProjectGroups(
            recentSessions: Array(recentSessions),
            useRepoRoot: useRepoRoot
        )

        return ScanResult(
            projectGroups: groups,
            totalSessions: recentSessions.count
        )
    }

    private func buildProjectGroups(
        recentSessions: [SessionSnapshot],
        useRepoRoot: Bool
    ) -> [String: ProjectGroup] {
        let groupedByProject = Dictionary(grouping: recentSessions) { snapshot in
            ProjectResolver.normalizeProjectPath(from: snapshot.cwd, useRepoRoot: useRepoRoot)
        }
        let allProjectPaths = Array(groupedByProject.keys)

        return groupedByProject.reduce(into: [String: ProjectGroup]()) { result, entry in
            let projectPath = entry.key
            let sessionsSorted = entry.value.sorted { lhs, rhs in
                if lhs.latestEvent == rhs.latestEvent {
                    return lhs.sessionId < rhs.sessionId
                }
                return lhs.latestEvent > rhs.latestEvent
            }

            guard !sessionsSorted.isEmpty else {
                return
            }

            result[projectPath] = ProjectGroup(
                id: projectPath,
                displayName: ProjectResolver.displayName(
                    for: projectPath,
                    allProjectPaths: allProjectPaths
                ),
                projectPath: projectPath,
                sessions: sessionsSorted
            )
        }
    }

    private func processFile(
        at fileURL: URL,
        cutoffDate: Date,
        ignoredPrefixes: [String]
    ) {
        let fileName = fileURL.lastPathComponent
        let fallbackSessionId = CodexHistoryScannerSupport.deriveSessionId(from: fileName)
        guard let metadata = fileMetadata(for: fileURL) else {
            return
        }
        rehydrateSessionMetaIfNeeded(
            at: fileURL,
            fallbackSessionId: fallbackSessionId,
            ignoredPrefixes: ignoredPrefixes
        )
        if shouldSkipStaleFile(
            filePath: fileURL.path,
            modifiedAt: metadata.modifiedAt,
            cutoffDate: cutoffDate,
            fallbackSessionId: fallbackSessionId
        ) {
            return
        }
        let startOffset = scanStartOffset(
            filePath: fileURL.path,
            fileSize: metadata.fileSize,
            modifiedAt: metadata.modifiedAt,
            fallbackSessionId: fallbackSessionId
        )

        guard let stream = CodexHistoryScannerSupport.openFile(forReading: fileURL) else {
            return
        }
        defer { stream.closeFile() }

        if startOffset > 0 {
            try? stream.seek(toOffset: startOffset)
        }

        let unreadTailBytes = readEvents(
            from: stream,
            filePath: fileURL.path,
            cutoffDate: cutoffDate,
            fallbackSessionId: fallbackSessionId,
            ignoredPrefixes: ignoredPrefixes
        )
        let safeOffset =
            stream.offsetInFile >= UInt64(unreadTailBytes)
            ? stream.offsetInFile - UInt64(unreadTailBytes)
            : 0

        fileCursors[fileURL.path] = FileScanCursor(
            offset: safeOffset,
            fileSize: metadata.fileSize,
            modifiedAt: metadata.modifiedAt
        )
    }

    private func fileMetadata(for fileURL: URL) -> (fileSize: UInt64, modifiedAt: Date?)? {
        let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let attrs else {
            return (0, nil)
        }
        let fileSize = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let modifiedAt = attrs[.modificationDate] as? Date
        return (fileSize, modifiedAt)
    }

    private func scanStartOffset(
        filePath: String,
        fileSize: UInt64,
        modifiedAt: Date?,
        fallbackSessionId: String
    ) -> UInt64 {
        let tailStartOffset =
            fileSize > AppConstants.maxScanTailBytes
            ? fileSize - AppConstants.maxScanTailBytes
            : 0

        guard let previousCursor = fileCursors[filePath] else {
            return tailStartOffset
        }

        let hasSnapshotContext = sessionSnapshots[fallbackSessionId] != nil
        if previousCursor.fileSize == fileSize,
            previousCursor.modifiedAt == modifiedAt,
            hasSnapshotContext
        {
            if snapshotNeedsEventRebuild(for: fallbackSessionId) {
                return tailStartOffset
            }
            return fileSize
        }

        guard previousCursor.fileSize <= fileSize, previousCursor.offset <= fileSize else {
            return 0
        }

        let lag = fileSize - previousCursor.offset
        if previousCursor.offset == 0 && tailStartOffset > 0 {
            return tailStartOffset
        }
        if lag > AppConstants.maxScanTailBytes {
            return max(previousCursor.offset, tailStartOffset)
        }

        if previousCursor.offset > 0, !hasSnapshotContext {
            return tailStartOffset
        }

        return previousCursor.offset
    }

    private func snapshotNeedsEventRebuild(for sessionId: String) -> Bool {
        guard let snapshot = sessionSnapshots[sessionId] else {
            return true
        }
        return snapshot.latestAssistantEvent == nil && snapshot.latestUserEvent == nil
    }

    private func rehydrateSessionMetaIfNeeded(
        at fileURL: URL,
        fallbackSessionId: String,
        ignoredPrefixes: [String]
    ) {
        guard sessionSnapshots[fallbackSessionId] == nil else {
            return
        }
        if let cursor = fileCursors[fileURL.path], cursor.offset == 0 {
            return
        }
        guard let stream = CodexHistoryScannerSupport.openFile(forReading: fileURL) else {
            return
        }
        defer { stream.closeFile() }

        var buffer = Data()
        let chunk = 4096
        let maxBytesToScan = 64 * 1024
        var bytesScanned = 0

        while bytesScanned < maxBytesToScan,
            let line = CodexHistoryScannerSupport.readLine(
                from: stream,
                into: &buffer,
                chunk: chunk
            )
        {
            bytesScanned += line.utf8.count + 1
            guard line.contains("\"session_meta\"") else {
                continue
            }
            guard
                let envelope = CodexHistoryScannerSupport.parseEnvelope(
                    from: line,
                    fallbackSessionId: fallbackSessionId
                ),
                envelope.type == "session_meta",
                let eventTime = envelope.timestamp
            else {
                continue
            }

            applySessionMeta(
                envelope: envelope,
                filePath: fileURL.path,
                eventTime: eventTime,
                fallbackSessionId: fallbackSessionId,
                ignoredPrefixes: ignoredPrefixes
            )
            return
        }
    }

}
