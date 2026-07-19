import Foundation

@MainActor
final class BabyAlertRuleEngine: AlertRuleEvaluating {
    private var lastAlertDates: [String: Date] = [:]

    func evaluate(_ snapshot: MonitoringSnapshot, configuration: AlertRuleConfiguration) -> [AlertCandidate] {
        let candidates = rawCandidates(from: snapshot, configuration: configuration)
            .sorted { $0.severity > $1.severity }

        return candidates.filter { candidate in
            shouldEmit(candidate, cooldown: configuration.cooldownSeconds, now: snapshot.capturedAt)
        }
    }

    func resetCooldowns() {
        lastAlertDates.removeAll()
    }

    private func rawCandidates(from snapshot: MonitoringSnapshot, configuration: AlertRuleConfiguration) -> [AlertCandidate] {
        var candidates: [AlertCandidate] = []

        if snapshot.audio.classification == .crying && snapshot.audio.classificationConfidence >= 0.80 {
            candidates.append(
                AlertCandidate(
                    category: .audio,
                    severity: snapshot.audio.sustainedNoiseSeconds >= configuration.noiseDuration ? .critical : .warning,
                    title: "Baby crying detected",
                    detail: "Audio classification is crying at \(Int(snapshot.audio.classificationConfidence * 100))% confidence.",
                    confidence: snapshot.audio.classificationConfidence,
                    metadata: [
                        "classification": snapshot.audio.classification.rawValue,
                        "level": String(format: "%.2f", snapshot.audio.decibels)
                    ],
                    shouldNotify: true,
                    shouldEscalateToWatch: snapshot.audio.sustainedNoiseSeconds >= configuration.noiseDuration
                )
            )
        }

        if snapshot.audio.decibels >= configuration.noiseThreshold &&
            snapshot.audio.sustainedNoiseSeconds >= configuration.noiseDuration {
            candidates.append(
                AlertCandidate(
                    category: .audio,
                    severity: .critical,
                    title: "Sustained noise",
                    detail: "Audio remained above threshold for \(Int(snapshot.audio.sustainedNoiseSeconds)) seconds.",
                    confidence: max(snapshot.audio.classificationConfidence, snapshot.audio.decibels),
                    metadata: [
                        "duration": "\(Int(snapshot.audio.sustainedNoiseSeconds))",
                        "level": String(format: "%.2f", snapshot.audio.decibels)
                    ],
                    shouldNotify: true,
                    shouldEscalateToWatch: true
                )
            )
        }

        if snapshot.motion.activityScore <= configuration.stillnessThreshold &&
            snapshot.motion.sustainedStillnessSeconds >= configuration.stillnessDuration {
            candidates.append(
                AlertCandidate(
                    category: .motion,
                    severity: .critical,
                    title: "Prolonged low movement",
                    detail: "Motion stayed below threshold for \(Int(snapshot.motion.sustainedStillnessSeconds)) seconds.",
                    confidence: min(0.72 + snapshot.motion.sustainedStillnessSeconds / 240, 0.96),
                    metadata: [
                        "activity": String(format: "%.2f", snapshot.motion.activityScore),
                        "stillness": "\(Int(snapshot.motion.sustainedStillnessSeconds))"
                    ],
                    shouldNotify: true,
                    shouldEscalateToWatch: true
                )
            )
        }

        if !snapshot.camera.facePresent &&
            snapshot.motion.sustainedStillnessSeconds >= configuration.faceMissingStillnessDuration &&
            snapshot.audio.decibels < 0.20 {
            candidates.append(
                AlertCandidate(
                    category: .camera,
                    severity: .warning,
                    title: "No face or person detected",
                    detail: "Vision occupancy confidence is \(Int(snapshot.camera.occupancyConfidence * 100))% while motion and sound are low.",
                    confidence: max(0.70, 1 - snapshot.camera.occupancyConfidence),
                    metadata: [
                        "faceConfidence": String(format: "%.2f", snapshot.camera.faceConfidence),
                        "personConfidence": String(format: "%.2f", snapshot.camera.personConfidence)
                    ],
                    shouldNotify: true,
                    shouldEscalateToWatch: false
                )
            )
        }

        if snapshot.camera.isLowLight && configuration.lowLightEscalates {
            candidates.append(
                AlertCandidate(
                    category: .camera,
                    severity: .warning,
                    title: "Low light in room",
                    detail: "Camera visibility may be reduced. Check the nursery lighting.",
                    confidence: 0.65,
                    metadata: ["source": "camera"],
                    shouldNotify: false,
                    shouldEscalateToWatch: false
                )
            )
        }

        if let celsius = snapshot.temperature.celsius,
           celsius >= configuration.highTemperatureCelsius {
            candidates.append(
                AlertCandidate(
                    category: .temperature,
                    severity: celsius >= configuration.highTemperatureCelsius + 2 ? .critical : .warning,
                    title: "Nursery temperature high",
                    detail: "Temperature is \(String(format: "%.1f", celsius)) C.",
                    confidence: max(snapshot.temperature.confidence, 0.80),
                    metadata: [
                        "celsius": String(format: "%.1f", celsius)
                    ],
                    shouldNotify: true,
                    shouldEscalateToWatch: celsius >= configuration.highTemperatureCelsius + 2
                )
            )
        }

        if let humidity = snapshot.humidity.relativePercent,
           humidity <= configuration.lowHumidityPercent || humidity >= configuration.highHumidityPercent {
            let critical = humidity <= configuration.lowHumidityPercent - 8 || humidity >= configuration.highHumidityPercent + 10
            candidates.append(
                AlertCandidate(
                    category: .humidity,
                    severity: critical ? .critical : .warning,
                    title: humidity >= configuration.highHumidityPercent ? "Nursery humidity high" : "Nursery humidity low",
                    detail: "Relative humidity is \(String(format: "%.0f", humidity))%.",
                    confidence: max(snapshot.humidity.confidence, 0.72),
                    metadata: [
                        "relativeHumidity": String(format: "%.0f", humidity),
                        "targetRange": "\(Int(configuration.lowHumidityPercent))-\(Int(configuration.highHumidityPercent))"
                    ],
                    shouldNotify: true,
                    shouldEscalateToWatch: critical
                )
            )
        }

        return candidates
    }

    private func shouldEmit(_ candidate: AlertCandidate, cooldown: TimeInterval, now: Date) -> Bool {
        let key = "\(candidate.category.rawValue)-\(candidate.title)"
        if let last = lastAlertDates[key], now.timeIntervalSince(last) < cooldown {
            return false
        }
        lastAlertDates[key] = now
        return true
    }
}
