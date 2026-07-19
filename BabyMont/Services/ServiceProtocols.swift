import AVFoundation
import Foundation
import UIKit

@MainActor
protocol CameraMonitoringService: AnyObject {
    var signal: CameraSignal { get }
    var session: AVCaptureSession? { get }
    var latestFrame: VisionFrame? { get }
    func start() async
    func stop()
    func captureSnapshot() -> UIImage?
}

@MainActor
protocol AudioMonitoringService: AnyObject {
    var signal: AudioSignal { get }
    var latestEvent: AudioAnalysisEvent? { get }
    func start() async
    func stop()
}

@MainActor
protocol MotionMonitoringService: AnyObject {
    var signal: MotionSignal { get }
    func start() async
    func stop()
}

@MainActor
protocol AlertRuleEvaluating: AnyObject {
    func evaluate(_ snapshot: MonitoringSnapshot, configuration: AlertRuleConfiguration) -> [AlertCandidate]
    func resetCooldowns()
}

@MainActor
protocol EventStoreService {
    func save(_ event: BabyEvent)
    func recentEvents(limit: Int) -> [BabyEvent]
}

@MainActor
protocol PushNotificationServicing: AnyObject {
    var authorizationState: MonitoringState { get }
    var deviceToken: String? { get }
    func configure()
    func requestAuthorization() async
    func registerForRemoteNotifications()
    func sendLocalAlert(for candidate: AlertCandidate) async
    func apnsPayload(for candidate: AlertCandidate) -> [String: Any]
}

@MainActor
protocol WatchEscalationServicing: AnyObject {
    var state: MonitoringState { get }
    func configure()
    func escalate(_ candidate: AlertCandidate) async -> Bool
}

@MainActor
protocol CloudSyncServicing: AnyObject {
    var isAvailable: Bool { get }
    func configure() async
    func updateDeviceToken(_ token: String?) async
    func save(_ event: BabyEvent) async
    func fetchRecentEvents(limit: Int) async -> [BabyEvent]
}

@MainActor
protocol HomeAutomationServicing: AnyObject {
    var isAvailable: Bool { get }
    func configure() async
    func selectNurseryRoom(named roomName: String)
    func handle(_ candidate: AlertCandidate) async
}
