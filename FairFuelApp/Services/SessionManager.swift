import Foundation
import CoreLocation
import SwiftData

// Central orchestrator. Owns the session state machine.
// Driver identity comes from the local DriverProfile on this device.
// The NFC tag identifies the vehicle, not the driver.
@MainActor
final class SessionManager: ObservableObject {

    enum SessionState {
        case idle
        case starting
        case active(DrivingSession)
        case stopping(DrivingSession)
        case ended
    }

    @Published private(set) var state: SessionState = .idle

    private let bleService = BLEService()
    private let locationService = LocationService()
    private var stoppingTask: Task<Void, Never>?

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        bleService.delegate = self
        locationService.delegate = self
    }

    // MARK: - Public API

    // Called when the driver taps the vehicle's NFC tag.
    // vehicleTagURI: the full URI from the tag e.g. "fairfuel://vehicle/<UUID>"
    func startSession(vehicleTagURI: String) {
        guard case .idle = state else { return }
        state = .starting

        // Look up the vehicle by its tag URI
        let vehicleFetch = FetchDescriptor<Vehicle>(
            predicate: #Predicate { $0.nfcTagID == vehicleTagURI }
        )
        guard let vehicle = try? modelContext.fetch(vehicleFetch).first else {
            state = .idle
            return
        }

        // The driver is whoever owns this phone — fetch the single local profile
        let driverFetch = FetchDescriptor<DriverProfile>()
        guard let driver = try? modelContext.fetch(driverFetch).first else {
            // No profile set up yet — UI should have caught this before allowing a scan
            state = .idle
            return
        }

        let session = DrivingSession(driver: driver, vehicle: vehicle)
        modelContext.insert(session)

        bleService.startMonitoring()
        locationService.startTracking()

        state = .active(session)
    }

    func endSessionManually() {
        guard case .active(let session) = state else { return }
        finalizeSession(session)
    }

    // MARK: - Private

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

        bleService.stopMonitoring()
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
    nonisolated func bleService(_ service: BLEService, beaconPresenceChanged isPresent: Bool) {
        Task { @MainActor in
            if isPresent {
                if case .stopping(let session) = self.state {
                    self.cancelStoppingCountdown(for: session)
                }
            }
            // Absence alone is not enough to end the session; we also need immobility.
            // The combined check happens in the LocationService immobility callback.
        }
    }
}

// MARK: - LocationServiceDelegate

extension SessionManager: LocationServiceDelegate {
    nonisolated func locationService(_ service: LocationService, didUpdate location: CLLocation) {
        Task { @MainActor in
            guard case .active(let session) = self.state else { return }
            let point = TripPoint(location: location, session: session)
            self.modelContext.insert(point)
            self.updateSessionMetrics(session: session, newPoint: point)
        }
    }

    nonisolated func locationService(_ service: LocationService, didDetectImmobility seconds: TimeInterval) {
        Task { @MainActor in
            guard case .active(let session) = self.state else { return }
            // Both conditions required: vehicle stopped AND beacon gone
            if !self.bleService.isBeaconPresent {
                self.beginStoppingCountdown(for: session)
            }
        }
    }

    private func updateSessionMetrics(session: DrivingSession, newPoint: TripPoint) {
        guard let prevPoint = session.points.dropLast().last else { return }
        let prev = CLLocation(latitude: prevPoint.latitude, longitude: prevPoint.longitude)
        let curr = CLLocation(latitude: newPoint.latitude, longitude: newPoint.longitude)
        session.distanceKm += prev.distance(from: curr) / 1000.0

        let deltaSpeed = newPoint.speedMps - prevPoint.speedMps
        if deltaSpeed > 2.2 { session.aggressiveAccelEvents += 1 }
        if deltaSpeed < -2.2 { session.hardBrakeEvents += 1 }
    }
}
