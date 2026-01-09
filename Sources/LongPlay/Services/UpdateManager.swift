import Foundation
import Sparkle
import UserNotifications

@MainActor
final class UpdateManager: NSObject, ObservableObject {
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastCheckedAt: Date?

    private let updatesEnabled: Bool
    private enum DefaultsKey {
        static let automaticallyChecks = "LongPlayAutomaticallyChecksForUpdates"
        static let automaticallyDownloads = "LongPlayAutomaticallyDownloadsUpdates"
        static let notifyWhenAvailable = "LongPlayNotifyWhenUpdateAvailable"
    }

    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: updatesEnabled,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }()

    init(updatesEnabled: Bool = true) {
        self.updatesEnabled = updatesEnabled
        super.init()

        if updatesEnabled {
            _ = updaterController
        }

        configureDefaultsIfNeeded()
    }

    var automaticallyChecksForUpdates: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.automaticallyChecks) }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.automaticallyChecks)
            updaterController.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.automaticallyDownloads) }
        set {
            UserDefaults.standard.set(newValue, forKey: DefaultsKey.automaticallyDownloads)
            updaterController.updater.automaticallyDownloadsUpdates = newValue
        }
    }

    var notifyWhenUpdateAvailable: Bool {
        get { UserDefaults.standard.bool(forKey: DefaultsKey.notifyWhenAvailable) }
        set { UserDefaults.standard.set(newValue, forKey: DefaultsKey.notifyWhenAvailable) }
    }

    func configureDefaultsIfNeeded() {
        let defaults: [String: Any] = [
            DefaultsKey.automaticallyChecks: true,
            DefaultsKey.automaticallyDownloads: true,
            DefaultsKey.notifyWhenAvailable: false,
        ]
        UserDefaults.standard.register(defaults: defaults)

        if updatesEnabled {
            updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            updaterController.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates
        }
    }

    func checkForUpdates() {
        guard updatesEnabled else {
            errorMessage = "Updates are disabled for this build."
            return
        }
        errorMessage = nil
        lastCheckedAt = Date()
        updaterController.checkForUpdates(nil)
    }

    func requestNotificationPermissionIfNeeded() async {
        guard notifyWhenUpdateAvailable else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    private nonisolated func postUpdateAvailableNotification() async {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.notifyWhenAvailable) else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Update Available"
        content.body = "A new version of LongPlay is ready to install."
        content.sound = .default
        content.userInfo = ["action": "checkForUpdates"]

        let request = UNNotificationRequest(
            identifier: "LongPlayUpdateAvailable",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}

extension UpdateManager: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { await self.postUpdateAvailableNotification() }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
        }
    }
}
