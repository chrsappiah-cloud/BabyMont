import Foundation
import AVFoundation
import SwiftData
import UIKit

@MainActor
struct AppDependencies {
    var camera: any CameraMonitoringService
    var audio: any AudioMonitoringService
    var motion: any MotionMonitoringService
    var alertRules: any AlertRuleEvaluating
    var eventStore: any EventStoreService
    var push: any PushNotificationServicing
    var watch: any WatchEscalationServicing
    var cloudSync: any CloudSyncServicing
    var homeAutomation: any HomeAutomationServicing

    static func live(modelContext: ModelContext) -> AppDependencies {
        AppDependencies(
            camera: LocalCameraMonitoringService(),
            audio: LocalAudioMonitoringService(),
            motion: LocalMotionMonitoringService(),
            alertRules: BabyAlertRuleEngine(),
            eventStore: SwiftDataEventStore(modelContext: modelContext),
            push: PushNotificationService.shared,
            watch: WatchEscalationService(),
            cloudSync: CloudKitCareTeamSyncService(),
            homeAutomation: HomeAutomationService()
        )
    }

    static var preview: AppDependencies {
        AppDependencies(
            camera: PreviewCameraMonitoringService(),
            audio: PreviewAudioMonitoringService(),
            motion: PreviewMotionMonitoringService(),
            alertRules: BabyAlertRuleEngine(),
            eventStore: InMemoryEventStore(),
            push: PreviewPushNotificationService(),
            watch: PreviewWatchEscalationService(),
            cloudSync: PreviewCloudSyncService(),
            homeAutomation: PreviewHomeAutomationService()
        )
    }
}

@MainActor
final class InMemoryEventStore: EventStoreService {
    private var events: [BabyEvent] = []

    func save(_ event: BabyEvent) {
        events.insert(event, at: 0)
    }

    func recentEvents(limit: Int) -> [BabyEvent] {
        Array(events.prefix(limit))
    }
}

@MainActor
final class PreviewCameraMonitoringService: CameraMonitoringService {
    private(set) var signal = CameraSignal(state: .idle)
    var session: AVCaptureSession? { nil }
    var latestFrame: VisionFrame? { nil }

    func start() async {
        signal = CameraSignal(
            state: .active,
            frameRate: 30,
            isLowLight: false,
            faceConfidence: 0.86,
            personConfidence: 0.91,
            occupancyConfidence: 0.91,
            capturedFrameCount: 24
        )
    }

    func stop() {
        signal = CameraSignal(state: .idle)
    }

    func captureSnapshot() -> UIImage? {
        nil
    }
}

@MainActor
final class PreviewAudioMonitoringService: AudioMonitoringService {
    private(set) var signal = AudioSignal(state: .idle)
    private(set) var latestEvent: AudioAnalysisEvent?

    func start() async {
        let event = AudioAnalysisEvent(timestamp: .now, classification: .ambient, confidence: 0.64, level: 0.32)
        latestEvent = event
        signal = AudioSignal(
            state: .active,
            decibels: 0.32,
            sustainedNoiseSeconds: 0,
            classification: .ambient,
            classificationConfidence: 0.64,
            lastEvent: event
        )
    }

    func stop() {
        latestEvent = nil
        signal = AudioSignal(state: .idle)
    }
}

@MainActor
final class PreviewMotionMonitoringService: MotionMonitoringService {
    private(set) var signal = MotionSignal(state: .idle)

    func start() async {
        signal = MotionSignal(state: .active, activityScore: 0.24, sustainedStillnessSeconds: 0)
    }

    func stop() {
        signal = MotionSignal(state: .idle)
    }
}

@MainActor
final class PreviewPushNotificationService: PushNotificationServicing {
    private(set) var authorizationState: MonitoringState = .active
    private(set) var deviceToken: String? = "preview-device-token"

    func configure() {}
    func requestAuthorization() async {}
    func registerForRemoteNotifications() {}
    func sendLocalAlert(for candidate: AlertCandidate) async {}
    func apnsPayload(for candidate: AlertCandidate) -> [String: Any] {
        ["preview": true, "severity": candidate.severity.rawValue]
    }
}

@MainActor
final class PreviewWatchEscalationService: WatchEscalationServicing {
    private(set) var state: MonitoringState = .active

    func configure() {}

    func escalate(_ candidate: AlertCandidate) async -> Bool {
        true
    }
}

@MainActor
final class DisabledCloudSyncService: CloudSyncServicing {
    private(set) var isAvailable = false

    func configure() async {}
    func updateDeviceToken(_ token: String?) async {}
    func save(_ event: BabyEvent) async {}
    func fetchRecentEvents(limit: Int) async -> [BabyEvent] { [] }
}

@MainActor
final class DisabledHomeAutomationService: HomeAutomationServicing {
    private(set) var isAvailable = false

    func configure() async {}
    func selectNurseryRoom(named roomName: String) {}
    func handle(_ candidate: AlertCandidate) async {}
}

@MainActor
final class PreviewCloudSyncService: CloudSyncServicing {
    private(set) var isAvailable = true
    private var events: [BabyEvent] = []

    func configure() async {}
    func updateDeviceToken(_ token: String?) async {}
    func save(_ event: BabyEvent) async {
        events.insert(event, at: 0)
    }

    func fetchRecentEvents(limit: Int) async -> [BabyEvent] {
        Array(events.prefix(limit))
    }
}

@MainActor
final class PreviewHomeAutomationService: HomeAutomationServicing {
    private(set) var isAvailable = true

    func configure() async {}
    func selectNurseryRoom(named roomName: String) {}
    func handle(_ candidate: AlertCandidate) async {}
}
