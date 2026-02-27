import Foundation

extension CodexHistoryScanner {
    func candidateSessionFiles(cutoffDate: Date) -> [URL] {
        let fileManager = FileManager.default
        guard
            let enumerator = fileManager.enumerator(
                at: sessionsDirectory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        var files: [URL] = []
        for case let fileURL as URL in enumerator
        where AppConstants.sessionFileExtensions.contains(fileURL.pathExtension) {
            let path = fileURL.path
            let fallbackSessionId = CodexHistoryScannerSupport.deriveSessionId(from: fileURL.lastPathComponent)
            let attrs = try? fileManager.attributesOfItem(atPath: path)
            let modifiedAt = attrs?[.modificationDate] as? Date
            let hasSnapshotContext = sessionSnapshots[fallbackSessionId] != nil
            let hasRecentCursor: Bool
            if let cursorModifiedAt = fileCursors[path]?.modifiedAt {
                hasRecentCursor = cursorModifiedAt >= cutoffDate
            } else {
                hasRecentCursor = false
            }
            let isRecentlyModified = (modifiedAt ?? .distantPast) >= cutoffDate

            if isRecentlyModified || hasRecentCursor || hasSnapshotContext {
                files.append(fileURL)
            }
        }

        return files
    }

    func cleanupStaleFileCursors(keeping discoveredFilePaths: Set<String>) {
        fileCursors = fileCursors.filter { discoveredFilePaths.contains($0.key) }
    }

    func cleanupOrphanSnapshots(keeping discoveredFilePaths: Set<String>) {
        sessionSnapshots = sessionSnapshots.filter { _, snapshot in
            guard let sessionLogPath = snapshot.sessionLogPath else {
                return true
            }
            return discoveredFilePaths.contains(sessionLogPath)
        }
    }

    func cleanupStaleSnapshots(cutoffDate: Date) {
        let staleCutoff = cutoffDate.addingTimeInterval(-(AppConstants.snapshotRetentionHours * 3600))
        sessionSnapshots = sessionSnapshots.filter { $0.value.latestEvent >= staleCutoff }
    }

    func shouldSkipStaleFile(
        filePath: String,
        modifiedAt: Date?,
        cutoffDate: Date,
        fallbackSessionId: String
    ) -> Bool {
        guard sessionSnapshots[fallbackSessionId] == nil else {
            return false
        }
        guard let modifiedAt else {
            return false
        }
        guard modifiedAt < cutoffDate else {
            return false
        }
        if let cursor = fileCursors[filePath] {
            return cursor.modifiedAt == modifiedAt
        }
        return true
    }
}
