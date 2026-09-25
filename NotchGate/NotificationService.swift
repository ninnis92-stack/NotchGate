import Foundation
import UserNotifications

@Observable
final class NotificationPreferences {
    static let shared = NotificationPreferences()

    var lowBatteryAlerts: Bool {
        didSet { UserDefaults.standard.set(lowBatteryAlerts, forKey: "notch.alerts.lowBattery") }
    }
    var networkAlerts: Bool {
        didSet { UserDefaults.standard.set(networkAlerts, forKey: "notch.alerts.network") }
    }

    private init() {
        let defaults = UserDefaults.standard
        lowBatteryAlerts = defaults.object(forKey: "notch.alerts.lowBattery") as? Bool ?? false
        networkAlerts = defaults.object(forKey: "notch.alerts.network") as? Bool ?? false
    }
}

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private var lastBatteryAlertAt: Date?
    private var lastNetworkAlertAt: Date?
    private var previousNetworkState: Bool?

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            return (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        }
        return settings.authorizationStatus == .authorized
    }

    func evaluate(stats: SystemMonitor) {
        let preferences = NotificationPreferences.shared
        if preferences.lowBatteryAlerts,
           let battery = stats.batteryPercent,
           battery <= 20,
           !stats.isCharging,
           shouldSend(after: &lastBatteryAlertAt, minimumInterval: 6 * 60 * 60) {
            send(title: "Battery is low", body: "NotchGate reports (battery)% remaining.", identifier: "low-battery")
        }

        if preferences.networkAlerts,
           let previousNetworkState,
           previousNetworkState,
           !stats.wifiConnected,
           shouldSend(after: &lastNetworkAlertAt, minimumInterval: 30 * 60) {
            send(title: "Network connection changed", body: "NotchGate could not detect an active Wi‑Fi connection.", identifier: "network-offline")
        }
        previousNetworkState = stats.wifiConnected
    }

    private func shouldSend(after date: inout Date?, minimumInterval: TimeInterval) -> Bool {
        let now = Date()
        guard date.map({ now.timeIntervalSince($0) >= minimumInterval }) ?? true else { return false }
        date = now
        return true
    }

    private func send(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
