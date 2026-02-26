import Foundation
import CoreLocation
import SwiftData

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

    private let bleService = BLEService()
    private let locationService = LocationService()
    private var stoppingTask: Task<Void, Never>?

    // I require 3 consecutive GPS readings above the speed threshold before
    // committing to a session — avoids false starts when loading groceries near the car
    private var drivingConfirmationCount = 0
    private let confirmationsRequired = 3
    private let drivingSpeedThresholdMps: Double = 2.0  // ~7 km/h

    private let modelContext: ModelContext

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
        state = .pending(vehicle)
        locationService.startTracking()
        bleService.startRanging(beaconUUID: vehicle.beaconUUID)
    }

    private func cancelPending(vehicle: Vehicle) {
        bleService.stopRanging(beaconUUID: vehicle.beaconUUID)
        locationService.stopTracking()
        drivingConfirmationCount = 0
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
        session.endTime = Date()
        let efficiency = session.vehicle?.fuelEfficiencyLitersPer100Km ?? FuelEstimator.defaultLitersPer100Km
        session.estimatedFuelLiters = FuelEstimator.estimate(session: session, litersPer100Km: efficiency)
        if let beaconUUID = session.vehicle?.beaconUUID {
            bleService.stopRanging(beaconUUID: beaconUUID)
        }
        locationService.stopTracking()
        try? modelContext.save()
        state = .ended
        Task {
            try? await Task.sleep(for: .seconds(1))
            state = .idle
        }
    }
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
            }
            // absence alone doesn't end the session — LocationService immobility fires that
        }
    }
}

// MARK: - LocationServiceDelegate

extension SessionManager: LocationServiceDelegate {

    nonisolated func locationService(_ service: LocationService, didUpdate location: CLLocation) {
        Task { @MainActor in
            switch self.state {
            case .pending(let vehicle):
                // count consecutive readings above the driving threshold
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
                self.updateSessionMetrics(session: session, newPoint: point)

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

    private func updateSessionMetrics(session: DrivingSession, newPoint: TripPoint) {
        guard let prev = session.points.dropLast().last else { return }
        let prevLocation = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
        let currLocation = CLLocation(latitude: newPoint.latitude, longitude: newPoint.longitude)
        session.distanceKm += prevLocation.distance(from: currLocation) / 1000.0
        let deltaSpeed = newPoint.speedMps - prev.speedMps
        if deltaSpeed > 2.2 { session.aggressiveAccelEvents += 1 }
        if deltaSpeed < -2.2 { session.hardBrakeEvents += 1 }
    }
}
