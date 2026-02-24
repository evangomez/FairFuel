import Foundation
import CoreLocation

protocol LocationServiceDelegate: AnyObject {
    func locationService(_ service: LocationService, didUpdate point: CLLocation)
    func locationService(_ service: LocationService, didDetectImmobility seconds: TimeInterval)
}

final class LocationService: NSObject {
    weak var delegate: LocationServiceDelegate?

    private let locationManager = CLLocationManager()
    private var immobilityTimer: Timer?
    private let immobilityThresholdSeconds: TimeInterval = 180
    private let stoppedSpeedThresholdMps: Double = 1.0

    private(set) var isTracking = false

    // MARK: - Public

    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    func startTracking() {
        guard !isTracking else { return }
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .automotiveNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.startUpdatingLocation()
        isTracking = true
    }

    func stopTracking() {
        guard isTracking else { return }
        locationManager.stopUpdatingLocation()
        immobilityTimer?.invalidate()
        immobilityTimer = nil
        isTracking = false
    }

    // MARK: - Private

    private func handleSpeedUpdate(_ speedMps: Double) {
        if speedMps < stoppedSpeedThresholdMps {
            if immobilityTimer == nil {
                immobilityTimer = Timer.scheduledTimer(withTimeInterval: immobilityThresholdSeconds,
                                                       repeats: false) { [weak self] _ in
                    guard let self else { return }
                    self.delegate?.locationService(self, didDetectImmobility: self.immobilityThresholdSeconds)
                }
            }
        } else {
            immobilityTimer?.invalidate()
            immobilityTimer = nil
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        handleSpeedUpdate(max(0, location.speed))
        delegate?.locationService(self, didUpdate: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Log but don't crash; GPS may temporarily be unavailable (tunnel, etc.)
        print("[LocationService] error: \(error.localizedDescription)")
    }
}
