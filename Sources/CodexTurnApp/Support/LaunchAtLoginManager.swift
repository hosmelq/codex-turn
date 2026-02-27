import Foundation
import ServiceManagement

enum LaunchAtLoginManager {
    private static let preferenceKey = "launchAtLoginEnabled"

    static func savedPreference() -> Bool {
        UserDefaults.standard.bool(forKey: preferenceKey)
    }

    static func savePreference(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: preferenceKey)
    }

    static func isEnabled() -> Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        let service = SMAppService.mainApp

        do {
            if enabled {
                if !isEnabled() {
                    try service.register()
                }
            } else if isEnabled() {
                try service.unregister()
            }

            savePreference(enabled)
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    static func applySavedPreference() -> Bool {
        setEnabled(savedPreference())
    }
}
