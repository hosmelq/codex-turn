@testable import CodexTurnCore
import XCTest

final class CodexHistoryScannerRefreshTests: XCTestCase {
    func testScannerIncludesRecentFileInOlderDateDirectory() throws {
        let sessionsDirectory = try TestSupport.makeTemporaryDirectory(prefix: "sessions")
        defer { try? FileManager.default.removeItem(at: sessionsDirectory) }

        let oldDateDirectory = sessionsDirectory
            .appendingPathComponent("2024", isDirectory: true)
            .appendingPathComponent("01", isDirectory: true)
            .appendingPathComponent("01", isDirectory: true)
        try FileManager.default.createDirectory(at: oldDateDirectory, withIntermediateDirectories: true)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fileURL = oldDateDirectory.appendingPathComponent(
            "older-folder-f0fe3f30-4f17-415f-a8c7-c6e13a424cf0.jsonl"
        )

        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-180)),
                    "payload": [
                        "cwd": "/Users/me/work/older-folder-project",
                    ],
                ],
            ],
            to: fileURL
        )

        let scanner = CodexHistoryScanner(initialFileCursors: [:], sessionsDirectory: sessionsDirectory)
        let result = scanner.scanRecentSessions(
            by: now.addingTimeInterval(-3_600),
            useRepoRoot: false,
            ignoredPrefixes: []
        )

        XCTAssertEqual(result.projectGroups.count, 1)
        XCTAssertNotNil(result.projectGroups["/Users/me/work/older-folder-project"])
    }

    func testScannerExtractsGitBranchAndOriginMetadata() throws {
        let sessionsDirectory = try TestSupport.makeTemporaryDirectory(prefix: "sessions")
        defer { try? FileManager.default.removeItem(at: sessionsDirectory) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fileURL = sessionsDirectory.appendingPathComponent(
            "meta-9c0eec7e-835f-4a9f-8d91-57e9c63efcb8.jsonl"
        )

        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-180)),
                    "payload": [
                        "cwd": "/Users/me/work/project",
                        "git": [
                            "branch": "feature/thread-menu",
                        ],
                        "originator": "Codex Desktop",
                        "source": "vscode",
                    ],
                ],
            ],
            to: fileURL
        )

        let scanner = CodexHistoryScanner(initialFileCursors: [:], sessionsDirectory: sessionsDirectory)
        let result = scanner.scanRecentSessions(
            by: now.addingTimeInterval(-3_600),
            useRepoRoot: false,
            ignoredPrefixes: []
        )

        let session = try XCTUnwrap(result.projectGroups["/Users/me/work/project"]?.latestSession)
        XCTAssertEqual(session.gitBranch, "feature/thread-menu")
        XCTAssertEqual(session.originator, "Codex Desktop")
        XCTAssertEqual(session.source, "vscode")
    }

    func testScannerRemovesSnapshotsWhenSessionFileIsDeleted() throws {
        let sessionsDirectory = try TestSupport.makeTemporaryDirectory(prefix: "sessions")
        defer { try? FileManager.default.removeItem(at: sessionsDirectory) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fileURL = sessionsDirectory.appendingPathComponent(
            "deleted-3cf95e37-fb3a-45f0-99da-a8e7cf96f7e2.jsonl"
        )

        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-300)),
                    "payload": [
                        "cwd": "/Users/me/work/project",
                    ],
                ],
            ],
            to: fileURL
        )

        let scanner = CodexHistoryScanner(initialFileCursors: [:], sessionsDirectory: sessionsDirectory)
        let beforeDelete = scanner.scanRecentSessions(
            by: now.addingTimeInterval(-3_600),
            useRepoRoot: false,
            ignoredPrefixes: []
        )
        XCTAssertEqual(beforeDelete.projectGroups.count, 1)

        try FileManager.default.removeItem(at: fileURL)

        let afterDelete = scanner.scanRecentSessions(
            by: now.addingTimeInterval(-3_600),
            useRepoRoot: false,
            ignoredPrefixes: []
        )
        XCTAssertTrue(afterDelete.projectGroups.isEmpty)
        XCTAssertEqual(afterDelete.totalSessions, 0)
    }
}
