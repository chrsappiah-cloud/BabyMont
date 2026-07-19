import Combine
import AVFoundation
import Foundation
import UIKit

@MainActor
final class BabyMonitorViewModel: ObservableObject {
    @Published private(set) var snapshot = MonitoringSnapshot()
    @Published private(set) var recentEvents: [BabyEvent] = []
    @Published private(set) var activeAlerts: [AlertCandidate] = []
    @Published private(set) var isMonitoring = false
    @Published private(set) var statusMessage = "Local monitor ready"
    @Published private(set) var lastSnapshot: UIImage?
    @Published private(set) var cloudStatusMessage = "Cloud sync not checked"
    @Published private(set) var cloudEventCount = 0
    @Published private(set) var homeAutomationStatusMessage = "HomeKit not checked"
    @Published var alertConfiguration = AlertRuleConfiguration()

    private var dependencies: AppDependencies
    private var refreshTask: Task<Void, Never>?
    private var lastAudioEventDates: [AudioClassification: Date] = [:]

    init() {
        self.dependencies = .preview
    }

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    func configure(dependencies: AppDependencies) {
        self.dependencies = dependencies
        self.dependencies.push.configure()
        self.dependencies.watch.configure()
        recentEvents = dependencies.eventStore.recentEvents(limit: 12)
        cloudStatusMessage = dependencies.cloudSync.isAvailable ? "CloudKit available" : "Checking CloudKit"
        homeAutomationStatusMessage = dependencies.homeAutomation.isAvailable ? "HomeKit ready" : "Checking HomeKit"

        Task { [dependencies] in
            await dependencies.cloudSync.configure()
            await dependencies.homeAutomation.configure()
            dependencies.homeAutomation.selectNurseryRoom(named: "Nursery")
            refreshReadinessState()
        }
    }

    func requestNotificationReadiness() async {
        await dependencies.push.requestAuthorization()
        dependencies.push.registerForRemoteNotifications()
        await dependencies.cloudSync.updateDeviceToken(dependencies.push.deviceToken)
        await refreshCloudEvents()
        refreshReadinessState()
    }

    func startMonitoring() async {
        statusMessage = "Starting local camera, audio and motion services"
        await dependencies.camera.start()
        await dependencies.audio.start()
        await dependencies.motion.start()

        isMonitoring = true
        saveEvent(category: .system, severity: .info, title: "Monitoring started", detail: "Camera, audio and motion services are running locally.")
        startRefreshLoop()
    }

    func stopMonitoring() {
        dependencies.camera.stop()
        dependencies.audio.stop()
        dependencies.motion.stop()
        refreshTask?.cancel()
        refreshTask = nil
        isMonitoring = false
        activeAlerts = []
        dependencies.alertRules.resetCooldowns()
        lastAudioEventDates.removeAll()
        snapshot = MonitoringSnapshot()
        statusMessage = "Monitoring paused"
        saveEvent(category: .system, severity: .info, title: "Monitoring stopped", detail: "All local sensor services were paused.")
    }

    func simulateCriticalAlert() async {
        let candidate = AlertCandidate(
            category: .alert,
            severity: .critical,
            title: "Manual test alert",
            detail: "This verifies local notification and Apple Watch escalation paths.",
            confidence: 1,
            metadata: ["source": "manual_test"],
            shouldNotify: true,
            shouldEscalateToWatch: true
        )
        await handle(candidate)
    }

    func captureSnapshot() {
        guard let image = dependencies.camera.captureSnapshot() else {
            statusMessage = "No camera frame available for snapshot"
            return
        }

        lastSnapshot = image
        saveEvent(
            category: .camera,
            severity: .info,
            title: "Snapshot captured",
            detail: "A local nursery snapshot was captured for review.",
            confidence: dependencies.camera.signal.occupancyConfidence,
            metadata: ["source": "camera_snapshot"]
        )
    }

    func refreshCloudEvents() async {
        let events = await dependencies.cloudSync.fetchRecentEvents(limit: 12)
        cloudEventCount = events.count
        if dependencies.cloudSync.isAvailable {
            cloudStatusMessage = events.isEmpty ? "CloudKit ready" : "CloudKit synced \(events.count) events"
        } else {
            cloudStatusMessage = "CloudKit unavailable"
        }
    }

    var cameraSession: AVCaptureSession? {
        dependencies.camera.session
    }

    var pushAuthorizationState: MonitoringState {
        dependencies.push.authorizationState
    }

    var watchState: MonitoringState {
        dependencies.watch.state
    }

    var cloudIsAvailable: Bool {
        dependencies.cloudSync.isAvailable
    }

    var homeAutomationIsAvailable: Bool {
        dependencies.homeAutomation.isAvailable
    }

    var deviceTokenSummary: String {
        guard let token = dependencies.push.deviceToken, !token.isEmpty else {
            return "No device token"
        }
        return "\(token.prefix(8))..."
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refresh() async {
        snapshot = MonitoringSnapshot(
            camera: dependencies.camera.signal,
            audio: dependencies.audio.signal,
            motion: dependencies.motion.signal,
            temperature: TemperatureSignal(),
            humidity: HumiditySignal(),
            capturedAt: .now
        )

        persistAudioEventIfNeeded(snapshot.audio)

        let candidates = dependencies.alertRules.evaluate(snapshot, configuration: alertConfiguration)
        activeAlerts = candidates
        for candidate in candidates {
            await handle(candidate)
        }

        if candidates.isEmpty {
            statusMessage = snapshot.isRunning ? "Monitoring locally" : "Local monitor ready"
        }
    }

    private func handle(_ candidate: AlertCandidate) async {
        var didEscalate = false
        if candidate.shouldNotify {
            await dependencies.push.sendLocalAlert(for: candidate)
        }
        if candidate.shouldEscalateToWatch {
            didEscalate = await dependencies.watch.escalate(candidate)
        }
        await dependencies.homeAutomation.handle(candidate)

        let event = saveEvent(
            category: candidate.category,
            severity: candidate.severity,
            title: candidate.title,
            detail: candidate.detail,
            confidence: candidate.confidence,
            metadata: candidate.metadata,
            didEscalateToWatch: didEscalate,
            didRequestPush: candidate.shouldNotify,
            syncToCloud: false
        )
        await dependencies.cloudSync.save(event)
        if dependencies.cloudSync.isAvailable {
            cloudStatusMessage = "CloudKit saved \(event.title)"
            cloudEventCount += 1
        } else {
            cloudStatusMessage = "CloudKit unavailable"
        }

        statusMessage = candidate.severity == .critical ? "Critical alert escalated" : "Attention alert recorded"
    }

    private func refreshReadinessState() {
        cloudStatusMessage = dependencies.cloudSync.isAvailable ? "CloudKit ready" : "CloudKit unavailable"
        homeAutomationStatusMessage = dependencies.homeAutomation.isAvailable ? "HomeKit ready" : "HomeKit unavailable"
    }

    @discardableResult
    private func saveEvent(
        category: BabyEventCategory,
        severity: BabyEventSeverity,
        title: String,
        detail: String,
        confidence: Double = 1,
        metadata: [String: String] = [:],
        didEscalateToWatch: Bool = false,
        didRequestPush: Bool = false,
        syncToCloud: Bool = true
    ) -> BabyEvent {
        let event = BabyEvent(
            category: category,
            severity: severity,
            title: title,
            detail: detail,
            confidence: confidence,
            metadata: metadata,
            didEscalateToWatch: didEscalateToWatch,
            didRequestPush: didRequestPush
        )
        dependencies.eventStore.save(event)
        recentEvents = dependencies.eventStore.recentEvents(limit: 12)
        if syncToCloud {
            Task { [dependencies, event] in
                await dependencies.cloudSync.save(event)
            }
        }
        NotificationCenter.default.post(name: .babyEventRaised, object: event)
        return event
    }

    private func persistAudioEventIfNeeded(_ signal: AudioSignal) {
        guard let event = signal.lastEvent,
              event.classification != .ambient else {
            return
        }

        if let last = lastAudioEventDates[event.classification],
           Date.now.timeIntervalSince(last) < 30 {
            return
        }

        lastAudioEventDates[event.classification] = .now
        let severity: BabyEventSeverity
        switch event.classification {
        case .crying, .sustainedNoise:
            severity = .warning
        case .silence, .ambient:
            severity = .info
        }

        saveEvent(
            category: .audio,
            severity: severity,
            title: event.title,
            detail: "Audio classified as \(event.classification.title) at \(Int(event.confidence * 100))% confidence.",
            confidence: event.confidence,
            metadata: [
                "classification": event.classification.rawValue,
                "level": String(format: "%.2f", event.level)
            ]
        )
    }
}
