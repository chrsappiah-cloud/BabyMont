import Foundation
import SwiftData

enum BabyEventCategory: String, CaseIterable, Identifiable, Codable {
    case camera
    case audio
    case motion
    case temperature
    case humidity
    case alert
    case watch
    case system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: "Camera"
        case .audio: "Audio"
        case .motion: "Motion"
        case .temperature: "Temperature"
        case .humidity: "Humidity"
        case .alert: "Alert"
        case .watch: "Watch"
        case .system: "System"
        }
    }
}

enum BabyEventSeverity: String, CaseIterable, Identifiable, Codable, Comparable {
    case info
    case warning
    case critical

    var id: String { rawValue }

    private var rank: Int {
        switch self {
        case .info: 0
        case .warning: 1
        case .critical: 2
        }
    }

    static func < (lhs: BabyEventSeverity, rhs: BabyEventSeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    var title: String {
        switch self {
        case .info: "Info"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

@Model
final class BabyEvent {
    var id: UUID = UUID()
    var timestamp: Date = Date()
    var categoryRawValue: String = BabyEventCategory.system.rawValue
    var severityRawValue: String = BabyEventSeverity.info.rawValue
    var title: String = ""
    var detail: String = ""
    var confidence: Double = 1
    var metadataJSON: String = "{}"
    var didEscalateToWatch: Bool = false
    var didRequestPush: Bool = false

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        category: BabyEventCategory,
        severity: BabyEventSeverity,
        title: String,
        detail: String,
        confidence: Double = 1,
        metadata: [String: String] = [:],
        didEscalateToWatch: Bool = false,
        didRequestPush: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.categoryRawValue = category.rawValue
        self.severityRawValue = severity.rawValue
        self.title = title
        self.detail = detail
        self.confidence = confidence
        self.metadataJSON = Self.encode(metadata)
        self.didEscalateToWatch = didEscalateToWatch
        self.didRequestPush = didRequestPush
    }

    var category: BabyEventCategory {
        BabyEventCategory(rawValue: categoryRawValue) ?? .system
    }

    var severity: BabyEventSeverity {
        BabyEventSeverity(rawValue: severityRawValue) ?? .info
    }

    var metadata: [String: String] {
        guard let data = metadataJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func encode(_ metadata: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(metadata),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
