import Foundation
import CoreLocation
import SwiftData
import UIKit

@MainActor
final class SessionManager: NSObject, ObservableObject {

    enum SessionState {
        case idle
        case pending(Vehicle)       // beacon detected, confirming we're actually driving
        case active(DrivingSession)
        case stopping(DrivingSession)
        case ended
    }

    @Published private(set) var state: SessionState = .idle
    @Published private(set) var detectedBeaconUUIDs: Set<String> = []

    private let bleService = BLEService()
    private let locationService = LocationService()
    private var stoppingTask: Task<Void, Never>?

    // I require 3 consecutive GPS readings above the speed threshold before
    // committing to a session — avoids false starts when loading groceries near the car
    private var drivingConfirmationCount = 0
    private let confirmationsRequired = 1
    private let drivingSpeedThresholdMps: Double = 2.0  // ~7 km/h

    private let modelContext: ModelContext

    // Kept in memory so updateSessionMetrics never reads back from SwiftData's
    // unordered relationship array (which was causing 4x distance inflation).
    private var lastTrackedLocation: CLLocation?

    // Extends background execution time while waiting for GPS to confirm driving.
    // Ended as soon as the session confirms — at that point allowsBackgroundLocationUpdates
    // keeps the app alive for the duration of the trip.
    private var pendingBGTask: UIBackgroundTaskIdentifier = .invalid

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        super.init()
        bleService.delegate = self
        locationService.delegate = self
        loadAndMonitorVehicles()
    }

    // MARK: - Public

    func endSessionManually() {
        switch state {
        case .active(let session): finalizeSession(session)
        case .pending(let vehicle): cancelPending(vehicle: vehicle)
        default: break
        }
    }

    // Call this after adding a new vehicle so monitoring starts right away
    func beginMonitoring(vehicle: Vehicle) {
        bleService.startMonitoringRegion(beaconUUID: vehicle.beaconUUID)
        bleService.startSignificantLocationMonitoring()
    }

    // Call this after deleting a vehicle
    func stopMonitoring(vehicle: Vehicle) {
        bleService.stopMonitoringRegion(beaconUUID: vehicle.beaconUUID)
    }

    // MARK: - Private

    private func loadAndMonitorVehicles() {
        let vehicles = (try? modelContext.fetch(FetchDescriptor<Vehicle>())) ?? []
        for vehicle in vehicles {
            bleService.startMonitoringRegion(beaconUUID: vehicle.beaconUUID)
        }
        if !vehicles.isEmpty {
            bleService.startSignificantLocationMonitoring()
        }
    }

    private func vehicle(forBeaconUUID uuid: String) -> Vehicle? {
        let fetch = FetchDescriptor<Vehicle>(
            predicate: #Predicate { $0.beaconUUID == uuid }
        )
        return try? modelContext.fetch(fetch).first
    }

    private func localDriver() -> DriverProfile? {
        try? modelContext.fetch(FetchDescriptor<DriverProfile>()).first
    }

    private func enterPending(vehicle: Vehicle) {
        guard case .idle = state else { return }
        drivingConfirmationCount = 0
        detectedBeaconUUIDs.insert(vehicle.beaconUUID)
        state = .pending(vehicle)
        locationService.startTracking()
        bleService.startRanging(beaconUUID: vehicle.beaconUUID)
        // Request extra background time so GPS can warm up and confirm driving.
        // iOS gives ~10s after a region event — this extends it to ~30s.
        pendingBGTask = UIApplication.shared.beginBackgroundTask(withName: "PendingConfirmation") { [weak self] in
            self?.endPendingBGTask()
        }
        print("[Session] Pending — beacon detected for \(vehicle.name)")
    }

    private func endPendingBGTask() {
        guard pendingBGTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(pendingBGTask)
        pendingBGTask = .invalid
    }

    private func cancelPending(vehicle: Vehicle) {
        bleService.stopRanging(beaconUUID: vehicle.beaconUUID)
        locationService.stopTracking()
        drivingConfirmationCount = 0
        detectedBeaconUUIDs.remove(vehicle.beaconUUID)
        endPendingBGTask()
        state = .idle
    }

    private func confirmAndStartSession(vehicle: Vehicle) {
        guard let driver = localDriver() else {
            cancelPending(vehicle: vehicle)
            return
        }
        let session = DrivingSession(driver: driver, vehicle: vehicle)
        modelContext.insert(session)
        state = .active(session)
        // GPS is now running with allowsBackgroundLocationUpdates — it keeps the app
        // alive for the trip, so the pending background task is no longer needed.
        endPendingBGTask()
        print("[Session] Active — started for \(driver.name) in \(vehicle.name)")
    }

    private func beginStoppingCountdown(for session: DrivingSession) {
        guard case .active = state else { return }
        state = .stopping(session)
        stoppingTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            finalizeSession(session)
        }
    }

    private func cancelStoppingCountdown(for session: DrivingSession) {
        stoppingTask?.cancel()
        stoppingTask = nil
        state = .active(session)
    }

    private func finalizeSession(_ session: DrivingSession) {
        stoppingTask?.cancel()
        stoppingTask = nil
        lastTrackedLocation = nil
        session.endTime = Date()
        let efficiency = session.vehicle?.fuelEfficiencyLitersPer100Km ?? FuelEstimator.defaultLitersPer100Km
        session.estimatedFuelLiters = FuelEstimator.estimate(session: session, litersPer100Km: efficiency)
        if let beaconUUID = session.vehicle?.beaconUUID {
            bleService.stopRanging(beaconUUID: beaconUUID)
            detectedBeaconUUIDs.remove(beaconUUID)
        }
        locationService.stopTracking()
        try? modelContext.save()
        if let groupID = GroupManager.shared.groupID {
            Task { await CloudKitService.shared.pushSession(session, groupID: groupID) }
        }
        print("[Session] Ended — %.2f km, %.3f L estimated", session.distanceKm, session.estimatedFuelLiters)
        state = .ended
        Task {
            try? await Task.sleep(for: .seconds(1))
            state = .idle
        }
    }

    // MARK: - Debug

    #if DEBUG
    // Simulates walking up to the car without needing real beacon hardware.
    // Only available in debug builds.
    func simulateBeaconEntry() {
        guard let vehicle = (try? modelContext.fetch(FetchDescriptor<Vehicle>()))?.first else {
            print("[Debug] No vehicle saved — add one first in Profile & Vehicles")
            return
        }
        print("[Debug] Simulating beacon entry for \(vehicle.name)")
        enterPending(vehicle: vehicle)
    }

    func simulateBeaconExit() {
        print("[Debug] Simulating beacon exit")
        switch state {
        case .pending(let vehicle): cancelPending(vehicle: vehicle)
        case .active(let session): beginStoppingCountdown(for: session)
        default: break
        }
    }

    func simulateDrivingConfirmed() {
        guard case .pending(let vehicle) = state else {
            print("[Debug] Not in pending state")
            return
        }
        print("[Debug] Simulating driving confirmed")
        confirmAndStartSession(vehicle: vehicle)
    }
    #endif
}

// MARK: - BLEServiceDelegate

extension SessionManager: BLEServiceDelegate {

    nonisolated func bleService(_ service: BLEService, didEnterRegionForVehicle beaconUUID: String) {
        Task { @MainActor in
            guard let vehicle = self.vehicle(forBeaconUUID: beaconUUID) else { return }
            self.enterPending(vehicle: vehicle)
        }
    }

    nonisolated func bleService(_ service: BLEService, didExitRegionForVehicle beaconUUID: String) {
        Task { @MainActor in
            self.detectedBeaconUUIDs.remove(beaconUUID)
            // exit event during pending means I walked away without driving
            if case .pending(let vehicle) = self.state, vehicle.beaconUUID == beaconUUID {
                self.cancelPending(vehicle: vehicle)
            }
        }
    }

    nonisolated func bleService(_ service: BLEService, beaconPresenceChanged isPresent: Bool) {
        Task { @MainActor in
            if isPresent {
                if case .stopping(let session) = self.state {
                    self.cancelStoppingCountdown(for: session)
                }
            } else {
                // beacon gone for 90s — start the end countdown
                if case .active(let session) = self.state {
                    self.beginStoppingCountdown(for: session)
                }
            }
        }
    }
}

// MARK: - LocationServiceDelegate

extension SessionManager: LocationServiceDelegate {

    nonisolated func locationService(_ service: LocationService, didUpdate location: CLLocation) {
        Task { @MainActor in
            switch self.state {
            case .pending(let vehicle):
                // speed is -1 when GPS hasn't acquired a fix yet — skip rather than reset
                guard location.speed >= 0 else { break }
                if location.speed >= self.drivingSpeedThresholdMps {
                    self.drivingConfirmationCount += 1
                    if self.drivingConfirmationCount >= self.confirmationsRequired {
                        self.confirmAndStartSession(vehicle: vehicle)
                    }
                } else {
                    self.drivingConfirmationCount = 0
                }

            case .active(let session):
                let point = TripPoint(location: location, session: session)
                self.modelContext.insert(point)
                self.updateSessionMetrics(session: session, newLocation: location)

            default:
                break
            }
        }
    }

    nonisolated func locationService(_ service: LocationService, didDetectImmobility seconds: TimeInterval) {
        Task { @MainActor in
            guard case .active(let session) = self.state else { return }
            if !self.bleService.isBeaconPresent {
                self.beginStoppingCountdown(for: session)
            }
        }
    }

    private func updateSessionMetrics(session: DrivingSession, newLocation: CLLocation) {
        guard newLocation.horizontalAccuracy >= 0,
              newLocation.horizontalAccuracy < 30 else {
            print("[Metrics] rejected — accuracy \(Int(newLocation.horizontalAccuracy))m")
            return
        }

        let speedMps = max(0, newLocation.speed)

        if let prev = lastTrackedLocation {
            let distanceM = prev.distance(from: newLocation)
            print("[Metrics] acc=\(Int(newLocation.horizontalAccuracy))m dist=\(Int(distanceM))m speed=\(String(format:"%.1f",speedMps))m/s total=\(String(format:"%.3f",session.distanceKm))km")

            if distanceM > 5 {
                session.distanceKm += distanceM / 1000.0
            }

            let timeDelta = newLocation.timestamp.timeIntervalSince(prev.timestamp)
            if speedMps < 1.0 {
                session.idleSeconds += timeDelta
            }

            let prevSpeed = max(0, prev.speed)
            let deltaSpeed = speedMps - prevSpeed
            if deltaSpeed > 2.2 { session.aggressiveAccelEvents += 1 }
            if deltaSpeed < -2.2 { session.hardBrakeEvents += 1 }
        } else {
            print("[Metrics] first point — acc=\(Int(newLocation.horizontalAccuracy))m")
        }

        // Only advance the reference point when this reading passed the accuracy check
        lastTrackedLocation = newLocation
    }
}
