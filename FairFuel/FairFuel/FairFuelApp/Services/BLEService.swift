import Foundation
import CoreLocation

protocol BLEServiceDelegate: AnyObject {
    func bleService(_ service: BLEService, didEnterRegionForVehicle beaconUUID: String)
    func bleService(_ service: BLEService, didExitRegionForVehicle beaconUUID: String)
    func bleService(_ service: BLEService, beaconPresenceChanged isPresent: Bool)
}

final class BLEService: NSObject {

    weak var delegate: BLEServiceDelegate?

    // keyed by beacon UUID string so I can support multiple vehicles
    private var monitoredRegions: [String: CLBeaconRegion] = [:]
    private var absenceTimer: Timer?

    // 90s gives enough buffer for brief signal drops without prematurely ending a session
    private let absenceTimeoutSeconds: TimeInterval = 90

    private(set) var isBeaconPresent = false

    private let locationManager = CLLocationManager()

    override init() {
        super.init()
        locationManager.delegate = self
    }

    // MARK: - Region Monitoring

    // I use region monitoring instead of constant scanning — it's hardware-based and
    // barely touches battery. iOS wakes the app on entry/exit even if it was killed.
    func startMonitoringRegion(beaconUUID: String) {
        guard let uuid = UUID(uuidString: beaconUUID),
              monitoredRegions[beaconUUID] == nil else { return }

        locationManager.requestAlwaysAuthorization()

        let constraint = CLBeaconIdentityConstraint(uuid: uuid)
        let regionID = "fairfuel.\(beaconUUID)"
        let region = CLBeaconRegion(beaconIdentityConstraint: constraint, identifier: regionID)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        region.notifyEntryStateOnDisplay = true

        monitoredRegions[beaconUUID] = region
        locationManager.startMonitoring(for: region)

        // check immediately in case we're already inside the region
        locationManager.requestState(for: region)
    }

    func stopMonitoringRegion(beaconUUID: String) {
        guard let region = monitoredRegions[beaconUUID] else { return }
        locationManager.stopMonitoring(for: region)
        monitoredRegions.removeValue(forKey: beaconUUID)
    }

    func stopAllMonitoring() {
        monitoredRegions.keys.forEach { stopMonitoringRegion(beaconUUID: $0) }
    }

    // MARK: - Ranging

    // Ranging runs during an active session to detect when I've left the car.
    // More battery than region monitoring, but only active while driving.
    func startRanging(beaconUUID: String) {
        guard let uuid = UUID(uuidString: beaconUUID) else { return }
        let constraint = CLBeaconIdentityConstraint(uuid: uuid)
        locationManager.startRangingBeacons(satisfying: constraint)
        isBeaconPresent = true
    }

    func stopRanging(beaconUUID: String) {
        guard let uuid = UUID(uuidString: beaconUUID) else { return }
        let constraint = CLBeaconIdentityConstraint(uuid: uuid)
        locationManager.stopRangingBeacons(satisfying: constraint)
        absenceTimer?.invalidate()
        absenceTimer = nil
        isBeaconPresent = false
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

    private func beaconUUID(from region: CLRegion) -> String? {
        guard let beaconRegion = region as? CLBeaconRegion else { return nil }
        // strip the "fairfuel." prefix I added when creating the region
        return String(beaconRegion.identifier.dropFirst("fairfuel.".count))
    }
}

// MARK: - CLLocationManagerDelegate

extension BLEService: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let uuid = beaconUUID(from: region) else { return }
        delegate?.bleService(self, didEnterRegionForVehicle: uuid)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let uuid = beaconUUID(from: region) else { return }
        delegate?.bleService(self, didExitRegionForVehicle: uuid)
    }

    // called by requestState(for:) on app launch — handles the case where
    // the app was killed and relaunched while I'm already inside the beacon region
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard state == .inside, let uuid = beaconUUID(from: region) else { return }
        delegate?.bleService(self, didEnterRegionForVehicle: uuid)
    }

    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon],
                         satisfying constraint: CLBeaconIdentityConstraint) {
        let visible = beacons.contains { $0.proximity != .unknown }
        visible ? handleBeaconSeen() : handleBeaconLost()
    }

    func locationManager(_ manager: CLLocationManager,
                         didFailRangingFor constraint: CLBeaconIdentityConstraint, error: Error) {
        handleBeaconLost()
    }
}
