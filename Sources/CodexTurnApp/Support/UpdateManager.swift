import Foundation
import Sparkle

@MainActor
final class UpdateManager {
    private let updaterController: SPUStandardUpdaterController
    private let isSparkleConfigured: Bool

    init() {
        isSparkleConfigured = Self.hasRequiredConfiguration()
        updaterController = SPUStandardUpdaterController(
            startingUpdater: isSparkleConfigured,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool {
        isSparkleConfigured
    }

    @discardableResult
    func checkForUpdates() -> Bool {
        guard isSparkleConfigured else {
            return false
        }

        updaterController.checkForUpdates(nil)
        return true
    }

    private static func hasRequiredConfiguration() -> Bool {
        guard let infoDictionary = Bundle.main.infoDictionary else {
            return false
        }

        let feedURL = (infoDictionary["SUFeedURL"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let publicKey = (infoDictionary["SUPublicEDKey"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let feedURL, !feedURL.isEmpty else {
            return false
        }

        guard let publicKey, !publicKey.isEmpty else {
            return false
        }

        return true
    }
}
