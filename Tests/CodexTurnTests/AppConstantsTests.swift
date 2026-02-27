@testable import CodexTurnCore
import XCTest

final class AppConstantsTests: XCTestCase {
    func testResolveCodexHomeDefaultsToDotCodexWhenMissing() throws {
        let homeDirectory = try TestSupport.makeTemporaryDirectory(prefix: "home")
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let resolved = AppConstants.resolveCodexHomeDirectory(homeDirectory: homeDirectory.path)

        let expected = homeDirectory.appendingPathComponent(".codex", isDirectory: true).path
        XCTAssertEqual(resolved.path, expected)
    }

    func testResolveCodexHomeUsesDotCodexWhenSessionsExist() throws {
        let homeDirectory = try TestSupport.makeTemporaryDirectory(prefix: "home")
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let defaultHome = homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        let defaultSessions = defaultHome.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: defaultSessions, withIntermediateDirectories: true)

        let resolved = AppConstants.resolveCodexHomeDirectory(homeDirectory: homeDirectory.path)

        XCTAssertEqual(resolved.path, defaultHome.path)
    }
}
