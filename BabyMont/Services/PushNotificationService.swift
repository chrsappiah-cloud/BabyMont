import Foundation
import CryptoKit
import SwiftUI
import UserNotifications

@MainActor
final class PushNotificationService: NSObject, PushNotificationServicing, UNUserNotificationCenterDelegate {
    static let shared = PushNotificationService()

    private(set) var authorizationState: MonitoringState = .idle
    private(set) var deviceToken: String?

    func configure() {
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    func requestAuthorization() async {
        authorizationState = .requestingPermission
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            authorizationState = granted ? .active : .denied("Notifications were not allowed.")
        } catch {
            authorizationState = .failed(error.localizedDescription)
        }
    }

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func updateDeviceToken(_ token: Data) {
        deviceToken = token.map { String(format: "%02.2hhx", $0) }.joined()
    }

    func failDeviceTokenRegistration(_ error: Error) {
        authorizationState = .failed(error.localizedDescription)
    }

    func sendLocalAlert(for candidate: AlertCandidate) async {
        let content = UNMutableNotificationContent()
        content.title = candidate.severity == .critical ? "Critical baby alert" : "Baby warning"
        content.subtitle = candidate.title
        content.body = "\(candidate.detail) Confidence \(Int(candidate.confidence * 100))%."
        content.sound = candidate.severity == .critical ? .defaultCritical : .default
        content.categoryIdentifier = "BABY_ALERT"
        content.threadIdentifier = "nursery-alerts"
        content.userInfo = [
            "event_id": candidate.id.uuidString,
            "type": candidate.title,
            "severity": candidate.severity.rawValue,
            "confidence": candidate.confidence
        ].merging(candidate.metadata) { current, _ in current }

        let request = UNNotificationRequest(
            identifier: "baby-alert-\(candidate.id.uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            authorizationState = .failed(error.localizedDescription)
        }
    }

    func apnsPayload(for candidate: AlertCandidate) -> [String: Any] {
        let interruptionLevel = candidate.severity == .critical ? "critical" : "time-sensitive"
        let relevance = candidate.severity == .critical ? 1.0 : 0.75
        let collapseSeed = "\(candidate.category.rawValue)-\(candidate.title)"
        let collapseID = SHA256.hash(data: Data(collapseSeed.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
            .prefix(32)

        return [
            "aps": [
                "alert": [
                    "title": candidate.severity == .critical ? "Critical baby alert" : "Baby warning",
                    "subtitle": candidate.title,
                    "body": "\(candidate.detail) Confidence \(Int(candidate.confidence * 100))%."
                ],
                "sound": candidate.severity == .critical ? "default" : "default",
                "category": "BABY_ALERT",
                "thread-id": "nursery-alerts",
                "interruption-level": interruptionLevel,
                "relevance-score": relevance
            ],
            "event_id": candidate.id.uuidString,
            "event_type": candidate.title,
            "severity": candidate.severity.rawValue,
            "confidence": candidate.confidence,
            "metadata": candidate.metadata,
            "apns-collapse-id-template": String(collapseID)
        ]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    private func registerCategories() {
        let acknowledge = UNNotificationAction(
            identifier: "ACKNOWLEDGE_ALERT",
            title: "Acknowledge",
            options: []
        )
        let callPartner = UNNotificationAction(
            identifier: "CALL_PARTNER",
            title: "Call Partner",
            options: [.foreground]
        )
        let openStream = UNNotificationAction(
            identifier: "OPEN_LIVE_STREAM",
            title: "Open Live Stream",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: "BABY_ALERT",
            actions: [acknowledge, callPartner, openStream],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationService.shared.updateDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationService.shared.failDeviceTokenRegistration(error)
        }
    }
}
