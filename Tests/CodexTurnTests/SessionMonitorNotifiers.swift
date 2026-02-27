@testable import CodexTurnCore

final class FakeNotifier: ProjectNotifying {
    var notifications: [(title: String, body: String)] = []
    var requestPermissionCalls = 0

    func requestPermission() async throws {
        requestPermissionCalls += 1
    }

    func notify(title: String, body: String) async throws {
        notifications.append((title: title, body: body))
    }
}

final class WarmupFailingNotifier: ProjectNotifying {
    struct Failure: Error {}

    func requestPermission() async throws {}

    func notify(title _: String, body _: String) async throws {
        throw Failure()
    }
}

final class FailingNotifier: ProjectNotifying {
    struct Failure: Error {}

    func requestPermission() async throws {
        throw Failure()
    }

    func notify(title _: String, body _: String) async throws {
        throw Failure()
    }
}
