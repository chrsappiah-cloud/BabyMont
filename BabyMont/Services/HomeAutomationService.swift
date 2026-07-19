import Foundation
import HomeKit

@MainActor
final class HomeAutomationService: NSObject, HomeAutomationServicing {
    private let manager = HMHomeManager()
    private(set) var primaryHome: HMHome?
    private(set) var nurseryRoom: HMRoom?
    private(set) var isAvailable = false

    override init() {
        super.init()
        manager.delegate = self
    }

    func configure() async {
        isAvailable = !manager.homes.isEmpty
        primaryHome = manager.homes.first
    }

    func selectNurseryRoom(named roomName: String) {
        nurseryRoom = primaryHome?.rooms.first { $0.name.localizedCaseInsensitiveContains(roomName) }
    }

    func handle(_ candidate: AlertCandidate) async {
        guard isAvailable else { return }

        if candidate.severity == .critical {
            try? await triggerActionSet(named: "Nursery Alert")
        } else if candidate.category == .temperature {
            try? await setNurseryLight(on: true, brightness: 0.70)
        }
    }

    private func triggerActionSet(named name: String) async throws {
        guard let actionSet = primaryHome?.actionSets.first(where: { $0.name == name }) else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            primaryHome?.executeActionSet(actionSet) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func setNurseryLight(on: Bool, brightness: Float) async throws {
        guard let accessory = nurseryRoom?.accessories.first(where: { accessory in
            accessory.services.contains { service in
                service.serviceType == HMServiceTypeLightbulb
            }
        }) else { return }

        for service in accessory.services where service.serviceType == HMServiceTypeLightbulb {
            for characteristic in service.characteristics {
                if characteristic.characteristicType == HMCharacteristicTypePowerState {
                    try await write(on, to: characteristic)
                }
                if characteristic.characteristicType == HMCharacteristicTypeBrightness {
                    try await write(Int(brightness * 100), to: characteristic)
                }
            }
        }
    }

    private func write(_ value: Any, to characteristic: HMCharacteristic) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            characteristic.writeValue(value) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

extension HomeAutomationService: HMHomeManagerDelegate {
    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in
            self.primaryHome = manager.homes.first
            self.isAvailable = self.primaryHome != nil
        }
    }
}
