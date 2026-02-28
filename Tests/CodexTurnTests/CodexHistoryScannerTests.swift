@testable import CodexTurnCore
import XCTest

final class CodexHistoryScannerTests: XCTestCase {
    func testScannerUsesFullUUIDFallbackSessionId() throws {
        let sessionsDirectory = try TestSupport.makeTemporaryDirectory(prefix: "sessions")
        defer { try? FileManager.default.removeItem(at: sessionsDirectory) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fileURL = sessionsDirectory.appendingPathComponent(
            "2026-02-25T10-00-00-7e95fdcb-2f7a-4d66-85dd-dc15211a973a.jsonl"
        )

        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-900)),
                    "payload": [
                        "cwd": "/Users/me/work/app",
                    ],
                ],
                [
                    "type": "response_item",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-600)),
                    "payload": [
                        "item": [
                            "role": "user",
                        ],
                    ],
                ],
            ],
            to: fileURL
        )

        let scanner = CodexHistoryScanner(initialFileCursors: [:], sessionsDirectory: sessionsDirectory)
        let result = scanner.scanRecentSessions(
            by: now.addingTimeInterval(-3600),
            useRepoRoot: false,
            ignoredPrefixes: []
        )

        XCTAssertEqual(result.totalSessions, 1)
        let session = try XCTUnwrap(result.projectGroups["/Users/me/work/app"]?.latestSession)
        XCTAssertEqual(session.sessionId, "7e95fdcb-2f7a-4d66-85dd-dc15211a973a")
        XCTAssertEqual(session.state, .waiting)
        XCTAssertNotNil(session.latestUserEvent)
    }

    func testScannerRehydratesContextWhenResumingFromCursor() throws {
        let sessionsDirectory = try TestSupport.makeTemporaryDirectory(prefix: "sessions")
        defer { try? FileManager.default.removeItem(at: sessionsDirectory) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fileURL = sessionsDirectory.appendingPathComponent(
            "prefix-5cb1c9dc-6f7a-48c6-8faa-29b31d27f5f1.jsonl"
        )

        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-1_200)),
                    "payload": [
                        "cwd": "/Users/me/repo",
                    ],
                ],
                [
                    "type": "response_item",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-1_000)),
                    "payload": [
                        "role": "user",
                    ],
                ],
            ],
            to: fileURL
        )

        let scanner1 = CodexHistoryScanner(initialFileCursors: [:], sessionsDirectory: sessionsDirectory)
        _ = scanner1.scanRecentSessions(
            by: now.addingTimeInterval(-7200),
            useRepoRoot: false,
            ignoredPrefixes: []
        )
        let cursors = scanner1.currentFileCursors()

        try TestSupport.appendJSONLines(
            [
                [
                    "type": "response_item",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-300)),
                    "payload": [
                        "role": "assistant",
                    ],
                ],
            ],
            to: fileURL
        )

        let scanner2 = CodexHistoryScanner(initialFileCursors: cursors, sessionsDirectory: sessionsDirectory)
        let result = scanner2.scanRecentSessions(
            by: now.addingTimeInterval(-7200),
            useRepoRoot: false,
            ignoredPrefixes: []
        )

        let session = try XCTUnwrap(result.projectGroups["/Users/me/repo"]?.latestSession)
        XCTAssertEqual(session.state, .active)
        XCTAssertNotNil(session.latestAssistantEvent)
    }

    func testScannerDoesNotAdvanceCursorPastPartialJsonlTail() throws {
        let sessionsDirectory = try TestSupport.makeTemporaryDirectory(prefix: "sessions")
        defer { try? FileManager.default.removeItem(at: sessionsDirectory) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fileURL = sessionsDirectory.appendingPathComponent(
            "prefix-2a5790da-2ab6-4c9d-a4b7-312fb9687e22.jsonl"
        )

        let metaTimestamp = TestSupport.isoString(now.addingTimeInterval(-1_200))
        let userTimestamp = TestSupport.isoString(now.addingTimeInterval(-1_000))
        let metaLine =
            #"{"type":"session_meta","timestamp":"\#(metaTimestamp)","payload":{"cwd":"/Users/me/repo"}}"#
        let fullUserLine =
            #"{"type":"response_item","timestamp":"\#(userTimestamp)","payload":{"role":"user"}}"#

        let splitIndex = fullUserLine.index(fullUserLine.startIndex, offsetBy: fullUserLine.count - 4)
        let partialUserPrefix = String(fullUserLine[..<splitIndex])
        let partialUserSuffix = String(fullUserLine[splitIndex...])

        let initialContent = "\(metaLine)\n\(partialUserPrefix)"
        try initialContent.write(to: fileURL, atomically: true, encoding: .utf8)

        let scanner1 = CodexHistoryScanner(initialFileCursors: [:], sessionsDirectory: sessionsDirectory)
        let firstResult = scanner1.scanRecentSessions(
            by: now.addingTimeInterval(-7_200),
            useRepoRoot: false,
            ignoredPrefixes: []
        )

        let firstSession = try XCTUnwrap(firstResult.projectGroups["/Users/me/repo"]?.latestSession)
        XCTAssertNil(firstSession.latestUserEvent)

        let firstCursor = try XCTUnwrap(scanner1.currentFileCursors().values.first)
        let expectedOffset = UInt64("\(metaLine)\n".utf8.count)
        XCTAssertEqual(firstCursor.offset, expectedOffset)
        XCTAssertLessThan(firstCursor.offset, firstCursor.fileSize)

        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.seekToEnd()
        handle.write(Data("\(partialUserSuffix)\n".utf8))
        try handle.close()

        let scanner2 = CodexHistoryScanner(
            initialFileCursors: scanner1.currentFileCursors(),
            sessionsDirectory: sessionsDirectory
        )
        let secondResult = scanner2.scanRecentSessions(
            by: now.addingTimeInterval(-7_200),
            useRepoRoot: false,
            ignoredPrefixes: []
        )

        let secondSession = try XCTUnwrap(secondResult.projectGroups["/Users/me/repo"]?.latestSession)
        XCTAssertNotNil(secondSession.latestUserEvent)
        XCTAssertEqual(secondSession.state, .waiting)
    }

    func testScannerIgnoresConfiguredPrefixes() throws {
        let sessionsDirectory = try TestSupport.makeTemporaryDirectory(prefix: "sessions")
        defer { try? FileManager.default.removeItem(at: sessionsDirectory) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fileURL = sessionsDirectory.appendingPathComponent(
            "prefix-9f5a8e2a-7d47-4d63-9828-c7fc4a101a67.jsonl"
        )

        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-600)),
                    "payload": [
                        "cwd": "/tmp/scratch-project",
                    ],
                ],
            ],
            to: fileURL
        )

        let scanner = CodexHistoryScanner(initialFileCursors: [:], sessionsDirectory: sessionsDirectory)
        let result = scanner.scanRecentSessions(
            by: now.addingTimeInterval(-3600),
            useRepoRoot: false,
            ignoredPrefixes: AppConstants.ignorePathPrefixes
        )

        XCTAssertTrue(result.projectGroups.isEmpty)
        XCTAssertEqual(result.totalSessions, 0)
    }

    func testScannerGroupsByRepoRootWhenEnabled() throws {
        let sessionsDirectory = try TestSupport.makeTemporaryDirectory(prefix: "sessions")
        defer { try? FileManager.default.removeItem(at: sessionsDirectory) }

        let repoRoot = sessionsDirectory.appendingPathComponent("workspace/repo", isDirectory: true)
        let nested = repoRoot.appendingPathComponent("App/Feature", isDirectory: true)
        try FileManager.default.createDirectory(
            at: repoRoot.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let fileURL = sessionsDirectory.appendingPathComponent(
            "prefix-01b81273-79cd-4275-b40d-2a968f8ea61f.jsonl"
        )

        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-600)),
                    "payload": [
                        "cwd": nested.path,
                    ],
                ],
            ],
            to: fileURL
        )

        let scanner = CodexHistoryScanner(initialFileCursors: [:], sessionsDirectory: sessionsDirectory)
        let result = scanner.scanRecentSessions(
            by: now.addingTimeInterval(-3600),
            useRepoRoot: true,
            ignoredPrefixes: []
        )

        XCTAssertNotNil(result.projectGroups[repoRoot.path])
    }

    func testScannerGroupsCodexWorktreeByLinkedGitRepoRoot() throws {
        let sessionsDirectory = try TestSupport.makeTemporaryDirectory(prefix: "sessions")
        defer { try? FileManager.default.removeItem(at: sessionsDirectory) }

        let repoRoot = sessionsDirectory.appendingPathComponent("repos/example-repo", isDirectory: true)
        let codexWorktree = sessionsDirectory.appendingPathComponent(
            "workspaces/worktrees/40dc/example-repo",
            isDirectory: true
        )

        try FileManager.default.createDirectory(
            at: repoRoot.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: codexWorktree, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: repoRoot.appendingPathComponent(".git/worktrees/example-repo2", isDirectory: true),
            withIntermediateDirectories: true
        )

        let linkedWorktreeGitdir = repoRoot.appendingPathComponent(".git/worktrees/example-repo2").path
        try "gitdir: \(linkedWorktreeGitdir)\n".write(
            to: codexWorktree.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let mainFileURL = sessionsDirectory.appendingPathComponent(
            "main-a6d4eb18-c87c-4868-8078-d463bbf0f504.jsonl"
        )
        let worktreeFileURL = sessionsDirectory.appendingPathComponent(
            "worktree-2d9df89f-e14a-4348-a34a-985a7a5ec7e1.jsonl"
        )

        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-600)),
                    "payload": [
                        "cwd": repoRoot.path,
                    ],
                ],
            ],
            to: mainFileURL
        )

        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-300)),
                    "payload": [
                        "cwd": codexWorktree.path,
                    ],
                ],
            ],
            to: worktreeFileURL
        )

        let scanner = CodexHistoryScanner(initialFileCursors: [:], sessionsDirectory: sessionsDirectory)
        let grouped = scanner.scanRecentSessions(
            by: now.addingTimeInterval(-3_600),
            useRepoRoot: true,
            ignoredPrefixes: []
        )
        XCTAssertEqual(grouped.projectGroups.count, 1)
        XCTAssertNotNil(grouped.projectGroups[repoRoot.path])

        let ungrouped = scanner.scanRecentSessions(
            by: now.addingTimeInterval(-3_600),
            useRepoRoot: false,
            ignoredPrefixes: []
        )
        XCTAssertEqual(ungrouped.projectGroups.count, 2)
    }

}

final class CodexHistoryScannerSessionIdFallbackTests: XCTestCase {
    func testScannerUsesFallbackSessionIdForResponseItemsWithoutSessionId() throws {
        let sessionsDirectory = try TestSupport.makeTemporaryDirectory(prefix: "sessions")
        defer { try? FileManager.default.removeItem(at: sessionsDirectory) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sessionId = "7e95fdcb-2f7a-4d66-85dd-dc15211a973a"
        let fileURL = sessionsDirectory.appendingPathComponent(
            "2026-02-25T10-00-00-\(sessionId).jsonl"
        )

        try TestSupport.writeJSONLines(
            [
                [
                    "type": "session_meta",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-900)),
                    "payload": [
                        "cwd": "/Users/me/work/app",
                        "id": sessionId,
                    ],
                ],
                [
                    "type": "response_item",
                    "timestamp": TestSupport.isoString(now.addingTimeInterval(-600)),
                    "payload": [
                        "id": "msg_001",
                        "role": "user",
                        "content": [
                            [
                                "text": "Please add a test case",
                                "type": "input_text",
                            ],
                        ],
                    ],
                ],
            ],
            to: fileURL
        )

        let scanner = CodexHistoryScanner(initialFileCursors: [:], sessionsDirectory: sessionsDirectory)
        let result = scanner.scanRecentSessions(
            by: now.addingTimeInterval(-3600),
            useRepoRoot: false,
            ignoredPrefixes: []
        )

        XCTAssertEqual(result.totalSessions, 1)
        let project = try XCTUnwrap(result.projectGroups["/Users/me/work/app"])
        XCTAssertEqual(project.sessions.count, 1)
        let session = try XCTUnwrap(project.latestSession)
        XCTAssertEqual(session.sessionId, sessionId)
        XCTAssertNotNil(session.latestUserEvent)
        XCTAssertEqual(session.latestUserSummary, "Please add a test case")
    }
}
