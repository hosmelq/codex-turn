public protocol ProjectNotifying {
    func requestPermission() async throws
    func notify(title: String, body: String) async throws
    func openSystemNotificationSettings()
}

extension ProjectNotifying {
    public func openSystemNotificationSettings() {}
}
