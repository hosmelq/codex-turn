import AppKit
import CodexTurnCore
import Combine
import SwiftUI

@main
struct CodexTurnApp: App {
    @StateObject private var monitor: SessionMonitor
    @StateObject private var statusBarController: StatusBarController

    init() {
        let monitor = SessionMonitor()
        _monitor = StateObject(wrappedValue: monitor)
        _statusBarController = StateObject(wrappedValue: StatusBarController(monitor: monitor))
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(monitor)
        }
    }
}

extension SessionMonitor {
    convenience init() {
        self.init(notifier: ProjectNotifier())
    }
}

@MainActor
final class StatusBarController: NSObject, ObservableObject {
    private let monitor: SessionMonitor
    private let statusItem: NSStatusItem
    private let updateManager = UpdateManager()
    private var cancellables: Set<AnyCancellable> = []
    private var settingsWindowController: NSWindowController?

    init(monitor: SessionMonitor) {
        self.monitor = monitor
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem()
        bind()
        applyLaunchAtLoginPreference()
        rebuildMenu()
    }

    private func bind() {
        monitor.$projects
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        monitor.$statusText
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else {
            return
        }

        if let topBarIcon = loadTopBarIcon() {
            button.image = topBarIcon
        } else {
            let fallback = NSImage(
                systemSymbolName: "clock.badge.questionmark",
                accessibilityDescription: "CodexTurn"
            )
            fallback?.isTemplate = true
            button.image = fallback
        }

        button.imageScaling = .scaleProportionallyUpOrDown
        button.imagePosition = .imageOnly
        button.toolTip = "CodexTurn"
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let statusTextItem = NSMenuItem(title: monitor.statusText, action: nil, keyEquivalent: "")
        statusTextItem.isEnabled = false
        menu.addItem(statusTextItem)
        menu.addItem(.separator())

        if monitor.projects.isEmpty {
            let recencyWindowHours = Int(monitor.recencyWindowHours)
            let empty = NSMenuItem(
                title: "No recent sessions in last \(recencyWindowHours)h",
                action: nil,
                keyEquivalent: ""
            )
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for project in monitor.projects {
                menu.addItem(makeProjectItem(project))
            }
        }

        menu.addItem(.separator())

        let refresh = NSMenuItem(
            title: "Refresh now",
            action: #selector(refreshNow),
            keyEquivalent: "r"
        )
        refresh.target = self
        menu.addItem(refresh)
        menu.addItem(.separator())

        let actionsItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let actionsImage = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Actions")
        actionsImage?.isTemplate = true
        actionsItem.image = actionsImage
        actionsItem.submenu = makeActionsSubmenu()
        menu.addItem(actionsItem)

        self.statusItem.menu = menu
    }

    private func makeProjectItem(_ project: ProjectGroup) -> NSMenuItem {
        let sessions = monitor.sessions(for: project)
        let threadCount = sessions.count
        let threadLabel = threadCount == 1 ? "1 thread" : "\(threadCount) threads"
        let subtitle = "\(threadLabel) • last active \(monitor.projectLastActiveText(project))"

        let item = NSMenuItem(title: project.displayName, action: nil, keyEquivalent: "")
        item.attributedTitle = makeProjectAttributedTitle(name: project.displayName, subtitle: subtitle)
        item.submenu = makeProjectSubmenu(sessions)
        return item
    }

    private func makeProjectAttributedTitle(name: String, subtitle: String) -> NSAttributedString {
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor,
        ]
        let subtitleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]

        let result = NSMutableAttributedString(string: name, attributes: titleAttrs)
        result.append(NSAttributedString(string: "\n\(subtitle)", attributes: subtitleAttrs))
        return result
    }

    private func makeProjectSubmenu(_ sessions: [SessionSnapshot]) -> NSMenu {
        let submenu = NSMenu()

        if sessions.isEmpty {
            let empty = NSMenuItem(title: "No active threads", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            return submenu
        }

        for session in sessions {
            let row = ThreadMenuRow(
                badge: monitor.sessionBadgeText(session),
                iconName: monitor.sessionStatusIconName(session),
                isWaiting: monitor.sessionIsWaiting(session),
                message: monitor.sessionTitle(session),
                meta: monitor.sessionContextLine(session)
            )

            let host = NSHostingView(rootView: row)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)

            let item = NSMenuItem()
            item.isEnabled = false
            item.view = host
            submenu.addItem(item)
        }

        return submenu
    }

    private func makeActionsSubmenu() -> NSMenu {
        let submenu = NSMenu()

        let checkForUpdates = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkForUpdates.target = self
        checkForUpdates.isEnabled = updateManager.canCheckForUpdates
        submenu.addItem(checkForUpdates)
        submenu.addItem(.separator())

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settings.target = self
        submenu.addItem(settings)
        submenu.addItem(.separator())

        let about = NSMenuItem(
            title: "About CodexTurn",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        about.target = self
        submenu.addItem(about)
        submenu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quit.target = self
        submenu.addItem(quit)

        return submenu
    }

    @objc private func refreshNow() {
        Task { [weak self] in
            guard let self else { return }
            await self.monitor.refresh()
        }
    }

    @objc private func checkForUpdates() {
        _ = updateManager.checkForUpdates()
    }

    @objc private func showSettings() {
        presentSettingsWindow()
    }

    private func presentSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let settingsWindowController {
            settingsWindowController.showWindow(nil)
            settingsWindowController.window?.makeKeyAndOrderFront(nil)
            return
        }

        let content = SettingsView()
            .environmentObject(monitor)
        let contentController = NSHostingController(rootView: content)
        let settingsWindow = NSWindow(contentViewController: contentController)
        settingsWindow.title = "Settings"
        settingsWindow.styleMask = [.titled, .closable, .miniaturizable]
        settingsWindow.setContentSize(NSSize(width: 520, height: 560))
        settingsWindow.center()
        settingsWindow.isReleasedWhenClosed = false

        let controller = NSWindowController(window: settingsWindow)
        settingsWindowController = controller
        controller.showWindow(nil)
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    @objc private func showAbout() {
        AppActions.openAbout()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func applyLaunchAtLoginPreference() {
        guard LaunchAtLoginManager.applySavedPreference() else {
            let currentStatus = LaunchAtLoginManager.isEnabled()
            LaunchAtLoginManager.savePreference(currentStatus)
            monitor.statusText = "Could not apply start-at-login setting"
            return
        }
    }
}
