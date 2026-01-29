import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    func notifyDownloadComplete(track: Track) {
        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            switch settings.authorizationStatus {
            case .notDetermined:
                self.center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        DiagnosticsLogger.shared.log(level: "warning", message: "Notification permission failed: \(error)")
                    }
                    guard granted else { return }
                    self.scheduleDownloadNotification(for: track)
                }
            case .authorized, .provisional:
                self.scheduleDownloadNotification(for: track)
            case .denied, .ephemeral:
                break
            @unknown default:
                break
            }
        }
    }

    private func scheduleDownloadNotification(for track: Track) {
        let content = UNMutableNotificationContent()
        content.title = "Download complete"
        content.body = track.displayName
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { error in
            if let error {
                DiagnosticsLogger.shared.log(level: "warning", message: "Notification delivery failed: \(error)")
            }
        }
    }
}
