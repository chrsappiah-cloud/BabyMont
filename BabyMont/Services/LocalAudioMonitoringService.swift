import AVFoundation
import CoreML
import Foundation
import SoundAnalysis

@MainActor
final class LocalAudioMonitoringService: NSObject, AudioMonitoringService {
    private let engine = AVAudioEngine()
    private var analyzer: SNAudioStreamAnalyzer?
    private var analysisObserver: SoundClassificationObserver?
    private var audioFramePosition: AVAudioFramePosition = 0
    private var noiseStartedAt: Date?
    private var silenceStartedAt: Date?

    private(set) var signal = AudioSignal()
    private(set) var latestEvent: AudioAnalysisEvent?

    func start() async {
        signal.state = .requestingPermission

        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }

        guard granted else {
            signal.state = .denied("Microphone permission is required for local audio monitoring.")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
            installTapIfNeeded()
            try engine.start()
            signal.state = .active
        } catch {
            signal.state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        analyzer = nil
        analysisObserver = nil
        audioFramePosition = 0
        noiseStartedAt = nil
        silenceStartedAt = nil
        latestEvent = nil
        signal = AudioSignal(state: .idle)
    }

    private func installTapIfNeeded() {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        configureSoundAnalysis(format: format)

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let level = Self.normalizedLevel(from: buffer)
            let framePosition = self.audioFramePosition
            self.audioFramePosition += AVAudioFramePosition(buffer.frameLength)
            self.analyzer?.analyze(buffer, atAudioFramePosition: framePosition)

            Task { @MainActor in
                self.updateSignal(level: level)
            }
        }
    }

    private func configureSoundAnalysis(format: AVAudioFormat) {
        analyzer = SNAudioStreamAnalyzer(format: format)

        let modelURL = Bundle.main.url(forResource: "CryDetector", withExtension: "mlmodelc")
            ?? Bundle.main.url(forResource: "BabySoundClassifier", withExtension: "mlmodelc")

        guard let modelURL,
              let model = try? MLModel(contentsOf: modelURL),
              let request = try? SNClassifySoundRequest(mlModel: model) else {
            return
        }

        let observer = SoundClassificationObserver { [weak self] classification, confidence in
            Task { @MainActor in
                self?.applySoundAnalysis(classification: classification, confidence: confidence)
            }
        }

        do {
            try analyzer?.add(request, withObserver: observer)
            analysisObserver = observer
        } catch {
            signal.state = .failed(error.localizedDescription)
        }
    }

    private func updateSignal(level: Double) {
        let event = heuristicEvent(for: level)
        latestEvent = event
        signal.decibels = level
        signal.classification = event.classification
        signal.classificationConfidence = event.confidence
        signal.lastEvent = event
        signal.sustainedNoiseSeconds = noiseStartedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        signal.state = .active
    }

    private func applySoundAnalysis(classification: AudioClassification, confidence: Double) {
        guard confidence >= signal.classificationConfidence else { return }
        let event = AudioAnalysisEvent(
            timestamp: .now,
            classification: classification,
            confidence: confidence,
            level: signal.decibels
        )
        latestEvent = event
        signal.classification = classification
        signal.classificationConfidence = confidence
        signal.lastEvent = event
    }

    private func heuristicEvent(for level: Double) -> AudioAnalysisEvent {
        let now = Date.now
        if level >= 0.78 {
            noiseStartedAt = noiseStartedAt ?? now
            silenceStartedAt = nil
        } else if level <= 0.08 {
            silenceStartedAt = silenceStartedAt ?? now
            noiseStartedAt = nil
        } else {
            noiseStartedAt = nil
            silenceStartedAt = nil
        }

        let sustainedNoise = noiseStartedAt.map { now.timeIntervalSince($0) } ?? 0
        let sustainedSilence = silenceStartedAt.map { now.timeIntervalSince($0) } ?? 0

        if level >= 0.86 {
            return AudioAnalysisEvent(timestamp: now, classification: .crying, confidence: min(0.72 + level * 0.25, 0.98), level: level)
        }

        if sustainedNoise >= 6 {
            return AudioAnalysisEvent(timestamp: now, classification: .sustainedNoise, confidence: min(0.65 + sustainedNoise / 60, 0.94), level: level)
        }

        if sustainedSilence >= 10 {
            return AudioAnalysisEvent(timestamp: now, classification: .silence, confidence: min(0.70 + sustainedSilence / 60, 0.96), level: level)
        }

        return AudioAnalysisEvent(timestamp: now, classification: .ambient, confidence: 0.55, level: level)
    }

    private static func normalizedLevel(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for frame in 0..<frameLength {
            sum += channelData[frame] * channelData[frame]
        }

        let rms = sqrt(sum / Float(frameLength))
        return min(max(Double(rms) * 12, 0), 1)
    }
}

private final class SoundClassificationObserver: NSObject, SNResultsObserving {
    private let handler: (AudioClassification, Double) -> Void

    init(handler: @escaping (AudioClassification, Double) -> Void) {
        self.handler = handler
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult,
              let classification = result.classifications.max(by: { $0.confidence < $1.confidence }) else {
            return
        }

        handler(Self.map(classification.identifier), classification.confidence)
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {}

    func requestDidComplete(_ request: SNRequest) {}

    private static func map(_ identifier: String) -> AudioClassification {
        let normalized = identifier.lowercased()
        if normalized.contains("cry") || normalized.contains("infant") || normalized.contains("baby") {
            return .crying
        }
        if normalized.contains("silence") || normalized.contains("quiet") {
            return .silence
        }
        if normalized.contains("noise") || normalized.contains("scream") || normalized.contains("shout") {
            return .sustainedNoise
        }
        return .ambient
    }
}
