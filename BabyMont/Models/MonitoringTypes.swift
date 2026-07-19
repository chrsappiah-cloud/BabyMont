import Foundation
import CoreVideo

struct VisionFrame {
    var id = UUID()
    var timestamp: Date
    var pixelBuffer: CVPixelBuffer
}

enum MonitoringState: Equatable {
    case idle
    case requestingPermission
    case active
    case denied(String)
    case unavailable(String)
    case failed(String)

    var title: String {
        switch self {
        case .idle: "Idle"
        case .requestingPermission: "Requesting"
        case .active: "Active"
        case .denied: "Denied"
        case .unavailable: "Unavailable"
        case .failed: "Failed"
        }
    }

    var detail: String {
        switch self {
        case .idle: "Waiting"
        case .requestingPermission: "Permission prompt"
        case .active: "Local sensor running"
        case .denied(let message), .unavailable(let message), .failed(let message): message
        }
    }
}

struct CameraSignal: Equatable {
    var state: MonitoringState = .idle
    var frameRate: Double = 0
    var isLowLight: Bool = false
    var faceConfidence: Double = 0
    var personConfidence: Double = 0
    var occupancyConfidence: Double = 0
    var capturedFrameCount: Int = 0

    var facePresent: Bool {
        faceConfidence >= 0.55 || personConfidence >= 0.65
    }
}

enum AudioClassification: String, Codable, CaseIterable, Identifiable {
    case crying
    case sustainedNoise
    case silence
    case ambient

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crying: "Crying"
        case .sustainedNoise: "Sustained noise"
        case .silence: "Silence"
        case .ambient: "Ambient"
        }
    }
}

struct AudioSignal: Equatable {
    var state: MonitoringState = .idle
    var decibels: Double = 0
    var sustainedNoiseSeconds: TimeInterval = 0
    var classification: AudioClassification = .ambient
    var classificationConfidence: Double = 0
    var lastEvent: AudioAnalysisEvent?
}

struct MotionSignal: Equatable {
    var state: MonitoringState = .idle
    var activityScore: Double = 0
    var sustainedStillnessSeconds: TimeInterval = 0
}

struct TemperatureSignal: Equatable {
    var celsius: Double?
    var confidence: Double = 0
}

struct HumiditySignal: Equatable {
    var relativePercent: Double?
    var confidence: Double = 0
}

struct MonitoringSnapshot: Equatable {
    var camera: CameraSignal = CameraSignal()
    var audio: AudioSignal = AudioSignal()
    var motion: MotionSignal = MotionSignal()
    var temperature: TemperatureSignal = TemperatureSignal()
    var humidity: HumiditySignal = HumiditySignal()
    var capturedAt: Date = .now

    var isRunning: Bool {
        camera.state == .active || audio.state == .active || motion.state == .active
    }
}

struct AlertRuleConfiguration: Equatable {
    var noiseThreshold: Double = 0.68
    var noiseDuration: TimeInterval = 8
    var stillnessThreshold: Double = 0.08
    var stillnessDuration: TimeInterval = 60
    var faceMissingStillnessDuration: TimeInterval = 25
    var highTemperatureCelsius: Double = 30
    var lowHumidityPercent: Double = 30
    var highHumidityPercent: Double = 65
    var cooldownSeconds: TimeInterval = 45
    var lowLightEscalates: Bool = true
}

struct AlertCandidate: Identifiable, Equatable {
    var id = UUID()
    var category: BabyEventCategory
    var severity: BabyEventSeverity
    var title: String
    var detail: String
    var confidence: Double
    var metadata: [String: String] = [:]
    var shouldNotify: Bool
    var shouldEscalateToWatch: Bool
}

struct AudioAnalysisEvent: Identifiable, Equatable {
    var id = UUID()
    var timestamp: Date
    var classification: AudioClassification
    var confidence: Double
    var level: Double

    var title: String {
        classification.title
    }
}

extension Notification.Name {
    static let babyEventRaised = Notification.Name("babyEventRaised")
}
