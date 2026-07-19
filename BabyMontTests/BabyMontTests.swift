import AVFoundation
import Foundation
import SwiftData
import Testing
import UIKit
@testable import BabyMont

@MainActor
struct BabyMontDomainTests {
    @Test func babyEventStoresTypedValuesAndMetadata() {
        let event = BabyEvent(
            category: .audio,
            severity: .critical,
            title: "Baby crying detected",
            detail: "Audio classification is crying.",
            confidence: 0.95,
            metadata: ["source": "rule_engine", "classification": "crying"],
            didEscalateToWatch: true,
            didRequestPush: true
        )

        #expect(event.category == .audio)
        #expect(event.severity == .critical)
        #expect(event.confidence == 0.95)
        #expect(event.metadata["source"] == "rule_engine")
        #expect(event.metadata["classification"] == "crying")
        #expect(event.didEscalateToWatch)
        #expect(event.didRequestPush)
    }

    @Test func severityIsOrderedForAlertPrioritisation() {
        #expect(BabyEventSeverity.info < .warning)
        #expect(BabyEventSeverity.warning < .critical)
        #expect(BabyEventSeverity.critical > .info)
    }

    @Test func inMemoryStoreReturnsMostRecentEventsFirstAndRespectsLimit() {
        let store = InMemoryEventStore()
        let older = BabyEvent(category: .system, severity: .info, title: "Older", detail: "First event")
        let newer = BabyEvent(category: .alert, severity: .warning, title: "Newer", detail: "Second event")

        store.save(older)
        store.save(newer)

        let events = store.recentEvents(limit: 1)
        #expect(events.count == 1)
        #expect(events.first?.id == newer.id)
    }
}

@MainActor
struct BabyMontArchitectureIntegrationTests {
    @Test func allAlertUnitsPersistToSwiftDataAndRespondThroughBackendServices() async throws {
        let container = try ModelContainer(
            for: BabyEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let services = MockServices()
        let swiftDataStore = SwiftDataEventStore(modelContext: container.mainContext)
        let dependencies = AppDependencies(
            camera: services.camera,
            audio: services.audio,
            motion: services.motion,
            alertRules: BabyAlertRuleEngine(),
            eventStore: swiftDataStore,
            push: services.push,
            watch: services.watch,
            cloudSync: services.cloud,
            homeAutomation: services.home
        )
        let viewModel = BabyMonitorViewModel(dependencies: dependencies)

        await viewModel.startMonitoring()
        await viewModel.simulateAudioAlert()
        await viewModel.simulateMotionAlert()
        await viewModel.simulateHumidityAlert()
        await viewModel.captureSnapshot()
        await viewModel.simulateCriticalAlert()
        await viewModel.refreshCloudEvents()

        let persistedTitles = swiftDataStore.recentEvents(limit: 12).map(\.title)
        #expect(persistedTitles.contains("Monitoring started"))
        #expect(persistedTitles.contains("Crying"))
        #expect(persistedTitles.contains("Baby crying detected"))
        #expect(persistedTitles.contains("Prolonged low movement"))
        #expect(persistedTitles.contains("Nursery humidity high"))
        #expect(persistedTitles.contains("Snapshot captured"))
        #expect(persistedTitles.contains("Manual test alert"))

        #expect(services.push.sentAlerts.map(\.title).contains("Baby crying detected"))
        #expect(services.push.sentAlerts.map(\.title).contains("Prolonged low movement"))
        #expect(services.push.sentAlerts.map(\.title).contains("Nursery humidity high"))
        #expect(services.push.sentAlerts.map(\.title).contains("Manual test alert"))
        #expect(services.watch.escalatedAlerts.map(\.category).contains(.motion))
        #expect(services.watch.escalatedAlerts.map(\.category).contains(.humidity))
        #expect(services.watch.escalatedAlerts.map(\.category).contains(.alert))
        #expect(services.home.handledAlerts.map(\.category).contains(.audio))
        #expect(services.home.handledAlerts.map(\.category).contains(.motion))
        #expect(services.home.handledAlerts.map(\.category).contains(.humidity))
        #expect(services.cloud.savedEvents.map(\.title).contains("Baby crying detected"))
        #expect(services.cloud.savedEvents.map(\.title).contains("Prolonged low movement"))
        #expect(services.cloud.savedEvents.map(\.title).contains("Nursery humidity high"))
        #expect(services.cloud.savedEvents.map(\.title).contains("Snapshot captured"))
        #expect(services.cloud.savedEvents.map(\.title).contains("Manual test alert"))
        #expect(viewModel.recentEvents.map(\.title).contains("Manual test alert"))
        #expect(viewModel.cloudEventCount == services.cloud.savedEvents.count)
    }
}

@MainActor
struct BabyMontRuleEngineTests {
    @Test func alertRulesEscalateSustainedNoiseToWatchAndPush() {
        let engine = BabyAlertRuleEngine()
        let snapshot = MonitoringSnapshot(
            camera: CameraSignal(state: .active, frameRate: 30),
            audio: AudioSignal(state: .active, decibels: 0.90, sustainedNoiseSeconds: 12),
            motion: MotionSignal(state: .active, activityScore: 0.40),
            capturedAt: .now
        )

        let alerts = engine.evaluate(snapshot, configuration: AlertRuleConfiguration())

        #expect(alerts.count == 1)
        #expect(alerts.first?.title == "Sustained noise")
        #expect(alerts.first?.severity == .critical)
        #expect(alerts.first?.shouldNotify == true)
        #expect(alerts.first?.shouldEscalateToWatch == true)
    }

    @Test func cryingClassificationCreatesWarningBeforeSustainedThreshold() {
        let engine = BabyAlertRuleEngine()
        let snapshot = MonitoringSnapshot(
            camera: CameraSignal(state: .active, frameRate: 30, faceConfidence: 0.80),
            audio: AudioSignal(
                state: .active,
                decibels: 0.42,
                sustainedNoiseSeconds: 2,
                classification: .crying,
                classificationConfidence: 0.88
            ),
            motion: MotionSignal(state: .active, activityScore: 0.35),
            capturedAt: .now
        )

        let alerts = engine.evaluate(snapshot, configuration: AlertRuleConfiguration())

        #expect(alerts.count == 1)
        #expect(alerts.first?.title == "Baby crying detected")
        #expect(alerts.first?.severity == .warning)
        #expect(alerts.first?.category == .audio)
        #expect(alerts.first?.shouldEscalateToWatch == false)
    }

    @Test func lowSignalsProduceNoAlert() {
        let engine = BabyAlertRuleEngine()
        let snapshot = MonitoringSnapshot(
            camera: CameraSignal(state: .active, faceConfidence: 0.82, personConfidence: 0.90),
            audio: AudioSignal(state: .active, decibels: 0.10, sustainedNoiseSeconds: 0),
            motion: MotionSignal(state: .active, activityScore: 0.22),
            temperature: TemperatureSignal(celsius: 24, confidence: 0.90),
            humidity: HumiditySignal(relativePercent: 50, confidence: 0.90),
            capturedAt: .now
        )

        let alerts = engine.evaluate(snapshot, configuration: AlertRuleConfiguration())

        #expect(alerts.isEmpty)
    }

    @Test func highTemperatureCreatesWarningAndCriticalEscalation() {
        let engine = BabyAlertRuleEngine()

        let warning = engine.evaluate(
            MonitoringSnapshot(
                camera: CameraSignal(state: .active, faceConfidence: 0.82),
                audio: AudioSignal(state: .active, decibels: 0.10),
                motion: MotionSignal(state: .active, activityScore: 0.20),
                temperature: TemperatureSignal(celsius: 30.2, confidence: 0.65),
                capturedAt: .now
            ),
            configuration: AlertRuleConfiguration()
        )

        engine.resetCooldowns()

        let critical = engine.evaluate(
            MonitoringSnapshot(
                camera: CameraSignal(state: .active, faceConfidence: 0.82),
                audio: AudioSignal(state: .active, decibels: 0.10),
                motion: MotionSignal(state: .active, activityScore: 0.20),
                temperature: TemperatureSignal(celsius: 32.1, confidence: 0.65),
                capturedAt: .now.addingTimeInterval(60)
            ),
            configuration: AlertRuleConfiguration()
        )

        #expect(warning.first?.title == "Nursery temperature high")
        #expect(warning.first?.severity == .warning)
        #expect(critical.first?.severity == .critical)
        #expect(critical.first?.shouldEscalateToWatch == true)
    }

    @Test func humidityOutsideHealthyRangeCreatesAlert() {
        let engine = BabyAlertRuleEngine()
        let snapshot = MonitoringSnapshot(
            camera: CameraSignal(state: .active, faceConfidence: 0.82),
            audio: AudioSignal(state: .active, decibels: 0.10),
            motion: MotionSignal(state: .active, activityScore: 0.20),
            humidity: HumiditySignal(relativePercent: 74, confidence: 0.81),
            capturedAt: .now
        )

        let alerts = engine.evaluate(snapshot, configuration: AlertRuleConfiguration())

        #expect(alerts.first?.category == .humidity)
        #expect(alerts.first?.title == "Nursery humidity high")
        #expect(alerts.first?.severity == .warning)
        #expect(alerts.first?.shouldNotify == true)
    }

    @Test func duplicateAlertsAreSuppressedUntilCooldownExpires() {
        let engine = BabyAlertRuleEngine()
        let configuration = AlertRuleConfiguration(cooldownSeconds: 45)
        let firstTime = Date(timeIntervalSince1970: 1_000)
        let snapshot = MonitoringSnapshot(
            camera: CameraSignal(state: .active),
            audio: AudioSignal(state: .active, decibels: 0.91, sustainedNoiseSeconds: 12),
            motion: MotionSignal(state: .active, activityScore: 0.35),
            capturedAt: firstTime
        )

        let first = engine.evaluate(snapshot, configuration: configuration)
        let duplicate = engine.evaluate(
            MonitoringSnapshot(camera: snapshot.camera, audio: snapshot.audio, motion: snapshot.motion, capturedAt: firstTime.addingTimeInterval(20)),
            configuration: configuration
        )
        let afterCooldown = engine.evaluate(
            MonitoringSnapshot(camera: snapshot.camera, audio: snapshot.audio, motion: snapshot.motion, capturedAt: firstTime.addingTimeInterval(50)),
            configuration: configuration
        )

        #expect(first.count == 1)
        #expect(duplicate.isEmpty)
        #expect(afterCooldown.count == 1)
    }
}

@MainActor
struct BabyMontNotificationTests {
    @Test func apnsPayloadContainsAlertActionsAndCollapseTemplate() {
        let service = PreviewPushNotificationService()
        let candidate = AlertCandidate(
            category: .audio,
            severity: .critical,
            title: "Baby crying detected",
            detail: "Audio classification is crying at 95% confidence.",
            confidence: 0.95,
            metadata: ["classification": "crying"],
            shouldNotify: true,
            shouldEscalateToWatch: true
        )

        let payload = service.apnsPayload(for: candidate)

        #expect(payload["severity"] as? String == "critical")
        #expect(payload["preview"] as? Bool == true)
    }

    @Test func liveApnsPayloadIncludesCriticalInterruptionLevel() {
        let service = PushNotificationService.shared
        let candidate = AlertCandidate(
            category: .audio,
            severity: .critical,
            title: "Baby crying detected",
            detail: "Audio classification is crying.",
            confidence: 0.95,
            metadata: ["classification": "crying"],
            shouldNotify: true,
            shouldEscalateToWatch: true
        )

        let payload = service.apnsPayload(for: candidate)
        let aps = try? #require(payload["aps"] as? [String: Any])
        let alert = try? #require(aps?["alert"] as? [String: String])

        #expect(aps?["category"] as? String == "BABY_ALERT")
        #expect(aps?["thread-id"] as? String == "nursery-alerts")
        #expect(aps?["interruption-level"] as? String == "critical")
        #expect(alert?["title"] == "Critical baby alert")
        #expect(payload["apns-collapse-id-template"] as? String != nil)
    }
}

@MainActor
struct BabyMonitorViewModelTests {
    @Test func startAndStopMonitoringCoordinateLocalServicesAndPersistEvents() async {
        let services = MockServices()
        let viewModel = BabyMonitorViewModel(dependencies: services.dependencies)

        await viewModel.startMonitoring()

        #expect(viewModel.isMonitoring == true)
        #expect(services.camera.didStart)
        #expect(services.audio.didStart)
        #expect(services.motion.didStart)
        #expect(services.store.savedEvents.contains { $0.title == "Monitoring started" })

        viewModel.stopMonitoring()

        #expect(viewModel.isMonitoring == false)
        #expect(services.camera.didStop)
        #expect(services.audio.didStop)
        #expect(services.motion.didStop)
        #expect(services.alertRules.didResetCooldowns)
        #expect(services.store.savedEvents.contains { $0.title == "Monitoring stopped" })
    }

    @Test func manualCriticalAlertUsesPushWatchHomeStoreAndCloud() async {
        let services = MockServices()
        let viewModel = BabyMonitorViewModel(dependencies: services.dependencies)

        await viewModel.simulateCriticalAlert()

        #expect(services.push.sentAlerts.count == 1)
        #expect(services.watch.escalatedAlerts.count == 1)
        #expect(services.home.handledAlerts.count == 1)
        #expect(services.store.savedEvents.first?.title == "Manual test alert")
        #expect(services.store.savedEvents.first?.didRequestPush == true)
        #expect(services.store.savedEvents.first?.didEscalateToWatch == true)
        #expect(services.cloud.savedEvents.contains { $0.title == "Manual test alert" })
        #expect(viewModel.statusMessage == "Critical alert escalated")
        #expect(viewModel.cloudStatusMessage == "CloudKit saved Manual test alert")
    }

    @Test func configurePreparesPushWatchCloudAndHome() async {
        let services = MockServices()
        let viewModel = BabyMonitorViewModel()

        viewModel.configure(dependencies: services.dependencies)
        await Task.yield()

        #expect(services.push.didConfigure)
        #expect(services.watch.didConfigure)
        #expect(services.cloud.didConfigure)
        #expect(services.home.selectedRoomName == "Nursery")
    }

    @Test func notificationReadinessUpdatesDeviceTokenAndCloudEvents() async {
        let services = MockServices()
        let viewModel = BabyMonitorViewModel(dependencies: services.dependencies)

        await viewModel.requestNotificationReadiness()

        #expect(services.push.didRequestAuthorization)
        #expect(services.push.didRegisterForRemoteNotifications)
        #expect(services.cloud.updatedDeviceTokens == ["mock-device-token"])
        #expect(viewModel.pushAuthorizationState == .active)
        #expect(viewModel.deviceTokenSummary == "mock-dev...")
        #expect(viewModel.cloudStatusMessage == "CloudKit ready")
    }

    @Test func refreshCloudEventsSurfacesFetchedCloudCount() async {
        let services = MockServices()
        services.cloud.seed([
            BabyEvent(category: .alert, severity: .warning, title: "Cloud warning", detail: "Fetched from CloudKit")
        ])
        let viewModel = BabyMonitorViewModel(dependencies: services.dependencies)

        await viewModel.refreshCloudEvents()

        #expect(viewModel.cloudEventCount == 1)
        #expect(viewModel.cloudStatusMessage == "CloudKit synced 1 events")
    }

    @Test func simulatedAudioAlertUsesRuleEngineNotificationStoreAndCloud() async {
        let services = MockServices()
        services.alertRules.candidates = [
            AlertCandidate(
                category: .audio,
                severity: .warning,
                title: "Baby crying detected",
                detail: "Audio classification is crying at 94% confidence.",
                confidence: 0.94,
                metadata: ["source": "audio_rule_engine", "classification": "crying"],
                shouldNotify: true,
                shouldEscalateToWatch: false
            )
        ]
        let viewModel = BabyMonitorViewModel(dependencies: services.dependencies)

        await viewModel.simulateAudioAlert()

        #expect(services.alertRules.evaluatedSnapshots.first?.audio.classification == .crying)
        #expect(services.alertRules.evaluatedSnapshots.first?.audio.classificationConfidence == 0.94)
        #expect(services.push.sentAlerts.first?.title == "Baby crying detected")
        #expect(services.home.handledAlerts.first?.category == .audio)
        #expect(services.store.savedEvents.contains { $0.title == "Crying" && $0.category == .audio })
        #expect(services.store.savedEvents.contains { $0.title == "Baby crying detected" && $0.didRequestPush })
        #expect(services.cloud.savedEvents.contains { $0.title == "Baby crying detected" })
        #expect(viewModel.statusMessage == "Attention alert recorded")
    }

    @Test func simulatedMotionAlertUsesRuleEngineNotificationStoreWatchAndCloud() async {
        let services = MockServices()
        services.alertRules.candidates = [
            AlertCandidate(
                category: .motion,
                severity: .critical,
                title: "Prolonged low movement",
                detail: "Motion stayed below threshold for 75 seconds.",
                confidence: 0.91,
                metadata: ["source": "motion_rule_engine", "stillness": "75"],
                shouldNotify: true,
                shouldEscalateToWatch: true
            )
        ]
        let viewModel = BabyMonitorViewModel(dependencies: services.dependencies)

        await viewModel.simulateMotionAlert()

        #expect(services.alertRules.evaluatedSnapshots.first?.motion.activityScore == 0.02)
        #expect(services.alertRules.evaluatedSnapshots.first?.motion.sustainedStillnessSeconds == 75)
        #expect(services.alertRules.evaluatedSnapshots.first?.camera.facePresent == true)
        #expect(services.push.sentAlerts.first?.title == "Prolonged low movement")
        #expect(services.watch.escalatedAlerts.first?.category == .motion)
        #expect(services.home.handledAlerts.first?.category == .motion)
        #expect(services.store.savedEvents.contains { $0.title == "Prolonged low movement" && $0.didEscalateToWatch })
        #expect(services.cloud.savedEvents.contains { $0.title == "Prolonged low movement" })
        #expect(viewModel.statusMessage == "Critical alert escalated")
    }

    @Test func simulatedHumidityAlertUsesRuleEngineNotificationStoreWatchAndCloud() async {
        let services = MockServices()
        services.alertRules.candidates = [
            AlertCandidate(
                category: .humidity,
                severity: .critical,
                title: "Nursery humidity high",
                detail: "Relative humidity is 77%.",
                confidence: 0.91,
                metadata: ["source": "humidity_rule_engine", "relativeHumidity": "77"],
                shouldNotify: true,
                shouldEscalateToWatch: true
            )
        ]
        let viewModel = BabyMonitorViewModel(dependencies: services.dependencies)

        await viewModel.simulateHumidityAlert()

        #expect(services.alertRules.evaluatedSnapshots.first?.humidity.relativePercent == 77)
        #expect(services.alertRules.evaluatedSnapshots.first?.humidity.confidence == 0.91)
        #expect(services.push.sentAlerts.first?.title == "Nursery humidity high")
        #expect(services.watch.escalatedAlerts.first?.category == .humidity)
        #expect(services.home.handledAlerts.first?.category == .humidity)
        #expect(services.store.savedEvents.contains { $0.title == "Nursery humidity high" && $0.didRequestPush })
        #expect(services.cloud.savedEvents.contains { $0.title == "Nursery humidity high" })
        #expect(viewModel.statusMessage == "Critical alert escalated")
    }

    @Test func snapshotCapturePersistsLocalImageEventAndCloudSync() async {
        let services = MockServices()
        let viewModel = BabyMonitorViewModel(dependencies: services.dependencies)

        await services.camera.start()
        await viewModel.captureSnapshot()

        #expect(viewModel.lastSnapshot != nil)
        #expect(viewModel.statusMessage == "Snapshot captured")
        #expect(viewModel.cloudStatusMessage == "CloudKit saved Snapshot captured")
        #expect(services.store.savedEvents.contains { event in
            event.title == "Snapshot captured" &&
            event.category == .camera &&
            event.metadata["source"] == "camera_snapshot" &&
            event.metadata["frameCount"] == "24"
        })
        #expect(services.cloud.savedEvents.contains { $0.title == "Snapshot captured" && $0.category == .camera })
    }
}

@MainActor
private final class MockServices {
    let camera = MockCameraMonitoringService()
    let audio = MockAudioMonitoringService()
    let motion = MockMotionMonitoringService()
    let alertRules = MockAlertRuleEvaluator()
    let store = MockEventStoreService()
    let push = MockPushNotificationService()
    let watch = MockWatchEscalationService()
    let cloud = MockCloudSyncService()
    let home = MockHomeAutomationService()

    var dependencies: AppDependencies {
        AppDependencies(
            camera: camera,
            audio: audio,
            motion: motion,
            alertRules: alertRules,
            eventStore: store,
            push: push,
            watch: watch,
            cloudSync: cloud,
            homeAutomation: home
        )
    }
}

@MainActor
private final class MockCameraMonitoringService: CameraMonitoringService {
    private(set) var signal = CameraSignal(state: .idle)
    var session: AVCaptureSession? { nil }
    var latestFrame: VisionFrame? { nil }
    var shouldReturnSnapshot = true
    private(set) var didStart = false
    private(set) var didStop = false

    func start() async {
        didStart = true
        signal = CameraSignal(
            state: .active,
            frameRate: 30,
            faceConfidence: 0.85,
            personConfidence: 0.92,
            occupancyConfidence: 0.92,
            capturedFrameCount: 24
        )
    }

    func stop() {
        didStop = true
        signal = CameraSignal(state: .idle)
    }

    func captureSnapshot() -> UIImage? {
        guard shouldReturnSnapshot else { return nil }
        return UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
    }
}

@MainActor
private final class MockAudioMonitoringService: AudioMonitoringService {
    private(set) var signal = AudioSignal(state: .idle)
    private(set) var latestEvent: AudioAnalysisEvent?
    private(set) var didStart = false
    private(set) var didStop = false

    func start() async {
        didStart = true
        latestEvent = AudioAnalysisEvent(timestamp: .now, classification: .ambient, confidence: 0.70, level: 0.20)
        signal = AudioSignal(state: .active, decibels: 0.20, classification: .ambient, classificationConfidence: 0.70, lastEvent: latestEvent)
    }

    func stop() {
        didStop = true
        latestEvent = nil
        signal = AudioSignal(state: .idle)
    }
}

@MainActor
private final class MockMotionMonitoringService: MotionMonitoringService {
    private(set) var signal = MotionSignal(state: .idle)
    private(set) var didStart = false
    private(set) var didStop = false

    func start() async {
        didStart = true
        signal = MotionSignal(state: .active, activityScore: 0.30)
    }

    func stop() {
        didStop = true
        signal = MotionSignal(state: .idle)
    }
}

@MainActor
private final class MockAlertRuleEvaluator: AlertRuleEvaluating {
    private(set) var didResetCooldowns = false
    private(set) var evaluatedSnapshots: [MonitoringSnapshot] = []
    var candidates: [AlertCandidate] = []

    func evaluate(_ snapshot: MonitoringSnapshot, configuration: AlertRuleConfiguration) -> [AlertCandidate] {
        evaluatedSnapshots.append(snapshot)
        return candidates
    }

    func resetCooldowns() {
        didResetCooldowns = true
    }
}

@MainActor
private final class MockEventStoreService: EventStoreService {
    private(set) var savedEvents: [BabyEvent] = []

    func save(_ event: BabyEvent) {
        savedEvents.insert(event, at: 0)
    }

    func recentEvents(limit: Int) -> [BabyEvent] {
        Array(savedEvents.prefix(limit))
    }
}

@MainActor
private final class MockPushNotificationService: PushNotificationServicing {
    private(set) var authorizationState: MonitoringState = .idle
    private(set) var deviceToken: String? = "mock-device-token"
    private(set) var didConfigure = false
    private(set) var didRequestAuthorization = false
    private(set) var didRegisterForRemoteNotifications = false
    private(set) var sentAlerts: [AlertCandidate] = []

    func configure() {
        didConfigure = true
    }

    func requestAuthorization() async {
        didRequestAuthorization = true
        authorizationState = .active
    }

    func registerForRemoteNotifications() {
        didRegisterForRemoteNotifications = true
    }

    func sendLocalAlert(for candidate: AlertCandidate) async {
        sentAlerts.append(candidate)
    }

    func apnsPayload(for candidate: AlertCandidate) -> [String: Any] {
        ["mock": true, "severity": candidate.severity.rawValue]
    }
}

@MainActor
private final class MockWatchEscalationService: WatchEscalationServicing {
    private(set) var state: MonitoringState = .idle
    private(set) var didConfigure = false
    private(set) var escalatedAlerts: [AlertCandidate] = []

    func configure() {
        didConfigure = true
        state = .active
    }

    func escalate(_ candidate: AlertCandidate) async -> Bool {
        escalatedAlerts.append(candidate)
        return true
    }
}

@MainActor
private final class MockCloudSyncService: CloudSyncServicing {
    private(set) var isAvailable = true
    private(set) var didConfigure = false
    private(set) var updatedDeviceTokens: [String?] = []
    private(set) var savedEvents: [BabyEvent] = []

    func configure() async {
        didConfigure = true
    }

    func updateDeviceToken(_ token: String?) async {
        updatedDeviceTokens.append(token)
    }

    func save(_ event: BabyEvent) async {
        savedEvents.insert(event, at: 0)
    }

    func fetchRecentEvents(limit: Int) async -> [BabyEvent] {
        Array(savedEvents.prefix(limit))
    }

    func seed(_ events: [BabyEvent]) {
        savedEvents = events
    }
}

@MainActor
private final class MockHomeAutomationService: HomeAutomationServicing {
    private(set) var isAvailable = true
    private(set) var didConfigure = false
    private(set) var selectedRoomName: String?
    private(set) var handledAlerts: [AlertCandidate] = []

    func configure() async {
        didConfigure = true
    }

    func selectNurseryRoom(named roomName: String) {
        selectedRoomName = roomName
    }

    func handle(_ candidate: AlertCandidate) async {
        handledAlerts.append(candidate)
    }
}
