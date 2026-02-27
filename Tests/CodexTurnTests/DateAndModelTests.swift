@testable import CodexTurnCore
import XCTest

final class DateAndModelTests: XCTestCase {
    func testTimeAgoDisplayAndWaitingDuration() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(now.addingTimeInterval(-20).timeAgoDisplay(now: now), "just now")
        XCTAssertEqual(now.addingTimeInterval(-300).timeAgoDisplay(now: now), "5m ago")
        XCTAssertEqual(now.addingTimeInterval(-7_200).timeAgoDisplay(now: now), "2h ago")
        XCTAssertEqual(now.addingTimeInterval(-172_800).timeAgoDisplay(now: now), "2d ago")

        XCTAssertEqual(now.addingTimeInterval(-120).waitingDurationDisplay(now: now), "2m")
        XCTAssertEqual(now.addingTimeInterval(-7_200).waitingDurationDisplay(now: now), "2h")
    }

    func testSessionSnapshotStateAndFingerprint() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var snapshot = SessionSnapshot(
            sessionId: "session",
            cwd: "/Users/me/project",
            firstSeen: now.addingTimeInterval(-1_000),
            latestEvent: now,
            latestUserEvent: now.addingTimeInterval(-300),
            latestAssistantEvent: nil,
            latestUserSummary: nil
        )

        XCTAssertEqual(snapshot.state, .waiting)
        let waitingSince = try XCTUnwrap(snapshot.latestUserEvent)
        XCTAssertLessThan(waitingSince, now)
        XCTAssertNotNil(snapshot.waitingSeconds)

        snapshot.latestAssistantEvent = now
        XCTAssertEqual(snapshot.state, .active)
        XCTAssertNil(snapshot.waitingSeconds)

        XCTAssertTrue(stateFingerprint(snapshot.latestUserEvent, snapshot.latestEvent).contains("waiting-"))
        XCTAssertTrue(stateFingerprint(nil, snapshot.latestEvent).contains("active-"))
    }

    func testSessionSnapshotStateWithoutUserEventIsActive() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = SessionSnapshot(
            sessionId: "session",
            cwd: "/Users/me/project",
            firstSeen: now.addingTimeInterval(-1_000),
            latestEvent: now,
            latestUserEvent: nil,
            latestAssistantEvent: nil,
            latestUserSummary: nil
        )

        XCTAssertEqual(snapshot.state, .active)
        XCTAssertNil(snapshot.waitingSeconds)
    }

    func testProjectGroupLastSeenFallsBackToDistantPast() {
        let project = ProjectGroup(
            id: "empty",
            displayName: "empty",
            projectPath: "/Users/me/empty",
            sessions: []
        )

        XCTAssertEqual(project.lastSeen, .distantPast)
        XCTAssertEqual(project.state, .idle)
    }

    func testProjectResolverDisplayAndRepoRootResolution() throws {
        let temp = try TestSupport.makeTemporaryDirectory(prefix: "resolver")
        defer { try? FileManager.default.removeItem(at: temp) }

        let repoRoot = temp.appendingPathComponent("repo", isDirectory: true)
        let repoGit = repoRoot.appendingPathComponent(".git", isDirectory: true)
        let nested = repoRoot.appendingPathComponent("Sources/App", isDirectory: true)
        try FileManager.default.createDirectory(at: repoGit, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let normalized = ProjectResolver.normalizeProjectPath(from: nested.path, useRepoRoot: true)
        XCTAssertEqual(normalized, repoRoot.path)

        let name1 = ProjectResolver.displayName(
            for: "/Users/me/work/a/project",
            allProjectPaths: ["/Users/me/work/a/project", "/Users/me/personal/b/project"]
        )
        XCTAssertEqual(name1, "project (a)")

        let name2 = ProjectResolver.displayName(
            for: "/Users/me/work/single",
            allProjectPaths: ["/Users/me/work/single"]
        )
        XCTAssertEqual(name2, "single")

        let name3 = ProjectResolver.displayName(
            for: "/Users/me/Work/40dc/example-repo",
            allProjectPaths: [
                "/Users/me/Work/40dc/example-repo",
                "/Users/me/Work/main/example-repo",
            ]
        )
        XCTAssertEqual(name3, "example-repo (40dc)")

        let mainRoot = temp.appendingPathComponent("repos/example-repo", isDirectory: true)
        let worktreeRoot = temp.appendingPathComponent(
            "workspaces/worktrees/40dc/example-repo",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mainRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: mainRoot.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: mainRoot.appendingPathComponent(".git/worktrees/example-repo2", isDirectory: true),
            withIntermediateDirectories: true
        )

        let linkedWorktreeGitdir = temp.appendingPathComponent(
            "repos/example-repo/.git/worktrees/example-repo2",
            isDirectory: true
        ).path
        try "gitdir: \(linkedWorktreeGitdir)\n".write(
            to: worktreeRoot.appendingPathComponent(".git"),
            atomically: true,
            encoding: .utf8
        )

        let mainDisplayName = ProjectResolver.displayName(
            for: mainRoot.path,
            allProjectPaths: [mainRoot.path, worktreeRoot.path]
        )
        XCTAssertEqual(mainDisplayName, "example-repo")

        let worktreeDisplayName = ProjectResolver.displayName(
            for: worktreeRoot.path,
            allProjectPaths: [mainRoot.path, worktreeRoot.path]
        )
        XCTAssertEqual(worktreeDisplayName, "example-repo (40dc)")

        let normalizedWorktree = ProjectResolver.normalizeProjectPath(
            from: worktreeRoot.path,
            useRepoRoot: true
        )
        XCTAssertEqual(normalizedWorktree, mainRoot.path)
    }

    func testExtractEnvironmentCwdRejectsCodeSnippetsAndParsesPaths() {
        let snippet =
            "let cwdStartRange = text.range(of: \"<cwd>\"), let cwdEndRange = text.range(of: \"</cwd>\")"
        XCTAssertNil(CodexHistoryScannerSupport.extractEnvironmentCwd(from: snippet))

        let directTags = "<cwd>/Users/me/project</cwd>"
        XCTAssertEqual(
            CodexHistoryScannerSupport.extractEnvironmentCwd(from: directTags),
            "/Users/me/project"
        )

        let environmentContext = """
            <environment_context>
              <cwd>/Users/me/workspace/repo</cwd>
              <shell>zsh</shell>
            </environment_context>
            """
        XCTAssertEqual(
            CodexHistoryScannerSupport.extractEnvironmentCwd(from: environmentContext),
            "/Users/me/workspace/repo"
        )

        let embeddedEnvironmentContext = """
            <system message>
            The following snippet is an example:
            <environment_context>
              <cwd>/Users/me/workspace/repo</cwd>
              <shell>zsh</shell>
            </environment_context>
            </system message>
            """
        XCTAssertNil(CodexHistoryScannerSupport.extractEnvironmentCwd(from: embeddedEnvironmentContext))
    }
}
