import CoreLocation
import Foundation

@MainActor
final class LocalLocationTrackingService: NSObject, LocationTrackingService {
    private let manager = CLLocationManager()
    private(set) var signal = LocationSignal(state: .idle)

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 25
        manager.activityType = .other
    }

    func requestAuthorization() async {
        guard CLLocationManager.locationServicesEnabled() else {
            signal = LocationSignal(state: .unavailable("Location Services disabled"))
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            signal = LocationSignal(state: .requestingPermission)
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            signal = signalWithState(.active, from: manager.location)
            manager.requestLocation()
        case .denied, .restricted:
            signal = LocationSignal(state: .denied("Location permission needed"))
        @unknown default:
            signal = LocationSignal(state: .failed("Unknown location authorization"))
        }
    }

    func start() async {
        await requestAuthorization()
        guard manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse else {
            return
        }
        manager.startUpdatingLocation()
        signal = signalWithState(.active, from: manager.location)
    }

    func stop() {
        manager.stopUpdatingLocation()
        signal = LocationSignal(state: .idle)
    }

    private func signalWithState(_ state: MonitoringState, from location: CLLocation?) -> LocationSignal {
        LocationSignal(
            state: state,
            latitude: location?.coordinate.latitude,
            longitude: location?.coordinate.longitude,
            horizontalAccuracyMeters: location?.horizontalAccuracy,
            capturedAt: location?.timestamp,
            locality: nil
        )
    }
}

extension LocalLocationTrackingService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                signal = signalWithState(.active, from: manager.location)
                manager.requestLocation()
            case .denied, .restricted:
                signal = LocationSignal(state: .denied("Location permission needed"))
            case .notDetermined:
                signal = LocationSignal(state: .requestingPermission)
            @unknown default:
                signal = LocationSignal(state: .failed("Unknown location authorization"))
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            signal = signalWithState(.active, from: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            signal = LocationSignal(state: .failed(error.localizedDescription))
        }
    }
}
