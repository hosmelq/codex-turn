@testable import CodexTurnCore
import XCTest

final class CodexHistoryScannerWorkspaceRootTests: XCTestCase {
    func testScannerRecoversWorkspaceRootFromSessionMetaWhenCwdIsRoot() throws {
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
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-600)),
                    "payload": [
                        "base_instructions": [
                            "text": "Workspace root: `/Users/me/Code/pickuphub.net`",
                        ],
                        "cwd": "/",
                        "id": "019c9641-6eb7-7652-9f6d-45d514962eec",
                    ],
                ],
                [
                    "type": "response_item",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-120)),
                    "payload": [
                        "content": [
                            [
                                "text": "Thanks!",
                                "type": "input_text",
                            ],
                        ],
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

        let project = try XCTUnwrap(result.projectGroups["/Users/me/Code/pickuphub.net"])
        let session = try XCTUnwrap(project.latestSession)
        XCTAssertNil(session.latestUserSummary)
        XCTAssertNotNil(session.latestAssistantEvent)
        XCTAssertEqual(session.latestAssistantSummary, "Thanks!")
    }

    func testScannerRecoversCwdFromStandaloneEnvironmentContextMessage() throws {
        let sessionsDirectory = try TestSupport.makeTemporaryDirectory(prefix: "sessions")
        defer { try? FileManager.default.removeItem(at: sessionsDirectory) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fileURL = sessionsDirectory.appendingPathComponent(
            "rollout-2026-02-26T13-20-04-019c9b64-dd67-7d32-820f-5c4e689e09c7.jsonl"
        )

        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-600)),
                    "payload": [
                        "cwd": "/",
                        "id": "019c9b64-dd67-7d32-820f-5c4e689e09c7",
                    ],
                ],
                [
                    "type": "response_item",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-300)),
                    "payload": [
                        "content": [
                            [
                                "text": """
                                <environment_context>
                                  <cwd>/Users/me/workspace/repo</cwd>
                                  <shell>zsh</shell>
                                </environment_context>
                                """,
                                "type": "input_text",
                            ],
                        ],
                        "role": "user",
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

        XCTAssertNotNil(result.projectGroups["/Users/me/workspace/repo"])
    }

    func testScannerIgnoresEmbeddedEnvironmentContextInsideSystemMessage() throws {
        let sessionsDirectory = try TestSupport.makeTemporaryDirectory(prefix: "sessions")
        defer { try? FileManager.default.removeItem(at: sessionsDirectory) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fileURL = sessionsDirectory.appendingPathComponent(
            "rollout-2026-02-26T13-20-04-019c9b64-dd67-7d32-820f-5c4e689e09c7.jsonl"
        )

        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-600)),
                    "payload": [
                        "cwd": "/",
                        "id": "019c9b64-dd67-7d32-820f-5c4e689e09c7",
                    ],
                ],
                [
                    "type": "response_item",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-300)),
                    "payload": [
                        "content": [
                            [
                                "text": """
                                <system message>
                                This is a prompt template example:
                                <environment_context>
                                  <cwd>/Users/me/workspace/repo</cwd>
                                  <shell>zsh</shell>
                                </environment_context>
                                </system message>
                                """,
                                "type": "input_text",
                            ],
                        ],
                        "role": "user",
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

        XCTAssertTrue(result.projectGroups.isEmpty)
    }
}
