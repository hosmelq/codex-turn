import Foundation

struct SessionScanResult {
    let fileCursors: [String: FileScanCursor]
    let result: ScanResult
}

actor SessionScanWorker {
    private let scanner: CodexHistoryScanner

    init(scanner: CodexHistoryScanner) {
        self.scanner = scanner
    }

    func setSessionsDirectory(_ directory: URL) -> Bool {
        scanner.setSessionsDirectory(directory)
    }

    func scan(
        by cutoffDate: Date,
        useRepoRoot: Bool,
        ignoredPrefixes: [String]
    ) -> SessionScanResult {
        let result = scanner.scanRecentSessions(
            by: cutoffDate,
            useRepoRoot: useRepoRoot,
            ignoredPrefixes: ignoredPrefixes
        )
        return SessionScanResult(
            fileCursors: scanner.currentFileCursors(),
            result: result
        )
    }
}
