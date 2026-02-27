import AppKit

@MainActor
enum AppActions {
    static func openAbout() {
        NSApp.activate(ignoringOtherApps: true)

        let info = Bundle.main.infoDictionary
        let build = info?["CFBundleVersion"] as? String ?? "1"
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"

        NSApp.orderFrontStandardAboutPanel(
            options: [
                .applicationName: "CodexTurn",
                .applicationVersion: version,
                .credits: NSAttributedString(string: "Copyright © Hosmel Quintana"),
                .version: build,
            ]
        )
    }
}
