import Foundation
import CoreLocation

// Monitors a BLE beacon using iBeacon ranging (CLLocationManager).
// Week 4 will tune thresholds and add Core Bluetooth fallback.
protocol BLEServiceDelegate: AnyObject {
    func bleService(_ service: BLEService, beaconPresenceChanged isPresent: Bool)
}

final class BLEService: NSObject {
    weak var delegate: BLEServiceDelegate?

    // Configure these UUIDs to match the vehicle's BLE beacon
    static let beaconUUID = UUID(uuidString: "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")!
    static let beaconRegionID = "com.fairfuel.vehicleBeacon"

    private let locationManager = CLLocationManager()
    private var beaconRegion: CLBeaconRegion?
    private var absenceTimer: Timer?

    // Duration of signal loss before declaring beacon absent
    private let absenceTimeoutSeconds: TimeInterval = 90

    private(set) var isBeaconPresent = false

    // MARK: - Public

    func startMonitoring() {
        locationManager.delegate = self
        let constraint = CLBeaconIdentityConstraint(uuid: BLEService.beaconUUID)
        beaconRegion = CLBeaconRegion(beaconIdentityConstraint: constraint, identifier: BLEService.beaconRegionID)
        guard let region = beaconRegion else { return }
        locationManager.startRangingBeacons(satisfying: constraint)
        locationManager.startMonitoring(for: region)
    }

    func stopMonitoring() {
        guard let region = beaconRegion else { return }
        let constraint = CLBeaconIdentityConstraint(uuid: BLEService.beaconUUID)
        locationManager.stopRangingBeacons(satisfying: constraint)
        locationManager.stopMonitoring(for: region)
        absenceTimer?.invalidate()
    }

    // MARK: - Private

    private func handleBeaconSeen() {
        absenceTimer?.invalidate()
        absenceTimer = nil
        if !isBeaconPresent {
            isBeaconPresent = true
            delegate?.bleService(self, beaconPresenceChanged: true)
        }
    }

    private func handleBeaconLost() {
        guard absenceTimer == nil else { return }
        absenceTimer = Timer.scheduledTimer(withTimeInterval: absenceTimeoutSeconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.isBeaconPresent = false
            self.delegate?.bleService(self, beaconPresenceChanged: false)
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension BLEService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon],
                         satisfying beaconConstraint: CLBeaconIdentityConstraint) {
        let visible = beacons.contains { $0.proximity != .unknown }
        visible ? handleBeaconSeen() : handleBeaconLost()
    }

    func locationManager(_ manager: CLLocationManager, didFailRangingFor beaconConstraint: CLBeaconIdentityConstraint,
                         error: Error) {
        handleBeaconLost()
    }
}
