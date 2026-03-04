@testable import CodexTurnCore
import XCTest

final class CodexHistoryScannerNamingTests: XCTestCase {
    func testScannerUsesGitRepositoryNameForCodenameCloneDisplayName() throws {
        let sessionsDirectory = try TestSupport.makeTemporaryDirectory(prefix: "sessions")
        defer { try? FileManager.default.removeItem(at: sessionsDirectory) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let clonePath = "/Users/me/.workspace/clones/5ce5359f/codename-clone"
        let fileURL = sessionsDirectory.appendingPathComponent(
            "scan-113afe1f-bceb-4e6a-918d-163cf5d51364.jsonl"
        )

        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-600)),
                    "payload": [
                        "cwd": clonePath,
                        "git": [
                            "repository_url": "git@github.com:example-org/example-repo.git",
                        ],
                    ],
                ],
                [
                    "type": "response_item",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-120)),
                    "payload": [
                        "role": "assistant",
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

        let project = try XCTUnwrap(result.projectGroups[clonePath])
        XCTAssertEqual(project.displayName, "example-repo")
    }
}
