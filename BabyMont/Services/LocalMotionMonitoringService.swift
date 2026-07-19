import CoreMotion
import Foundation

@MainActor
final class LocalMotionMonitoringService: MotionMonitoringService {
    private let manager = CMMotionManager()
    private var stillnessStartedAt: Date?
    private(set) var signal = MotionSignal()

    func start() async {
        guard manager.isDeviceMotionAvailable else {
            signal.state = .unavailable("Device motion is not available on this device.")
            return
        }

        signal.state = .active
        manager.deviceMotionUpdateInterval = 1
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }

            if let error {
                self.signal.state = .failed(error.localizedDescription)
                return
            }

            guard let motion else { return }
            self.updateSignal(from: motion)
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        stillnessStartedAt = nil
        signal = MotionSignal(state: .idle)
    }

    private func updateSignal(from motion: CMDeviceMotion) {
        let acceleration = motion.userAcceleration
        let magnitude = sqrt(
            acceleration.x * acceleration.x +
            acceleration.y * acceleration.y +
            acceleration.z * acceleration.z
        )
        let score = min(max(magnitude * 4, 0), 1)

        if score < 0.08 {
            stillnessStartedAt = stillnessStartedAt ?? .now
        } else {
            stillnessStartedAt = nil
        }

        signal.activityScore = score
        signal.sustainedStillnessSeconds = stillnessStartedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        signal.state = .active
    }
}
