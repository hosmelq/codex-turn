@testable import CodexTurnCore
import XCTest

final class CodexHistoryScannerRestartTests: XCTestCase {
    func testScannerRebuildsRecentEventsAfterRestartWhenFileIsUnchanged() throws {
        let sessionsDirectory = try TestSupport.makeTemporaryDirectory(prefix: "sessions")
        defer { try? FileManager.default.removeItem(at: sessionsDirectory) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fileURL = sessionsDirectory.appendingPathComponent(
            "rollout-2026-02-25T13-23-16-019c9641-6eb7-7652-9f6d-45d514962eec.jsonl"
        )

        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-7_200)),
                    "payload": [
                        "cwd": "/Users/me/restart-check",
                        "id": "019c9641-6eb7-7652-9f6d-45d514962eec",
                    ],
                ],
                [
                    "type": "response_item",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-600)),
                    "payload": [
                        "content": [
                            [
                                "text": "Need your review",
                                "type": "input_text",
                            ],
                        ],
                        "role": "user",
                    ],
                ],
            ],
            to: fileURL
        )

        let scanner1 = CodexHistoryScanner(initialFileCursors: [:], sessionsDirectory: sessionsDirectory)
        _ = scanner1.scanRecentSessions(
            by: now.addingTimeInterval(-10_800),
            useRepoRoot: false,
            ignoredPrefixes: []
        )
        let cursors = scanner1.currentFileCursors()

        let scanner2 = CodexHistoryScanner(initialFileCursors: cursors, sessionsDirectory: sessionsDirectory)
        let result = scanner2.scanRecentSessions(
            by: now.addingTimeInterval(-3_600),
            useRepoRoot: false,
            ignoredPrefixes: []
        )

        let session = try XCTUnwrap(result.projectGroups["/Users/me/restart-check"]?.latestSession)
        XCTAssertNotNil(session.latestUserEvent)
        XCTAssertEqual(session.latestUserSummary, "Need your review")
    }
}
