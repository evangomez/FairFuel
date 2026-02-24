import Foundation
import CoreLocation
import SwiftData

// Central orchestrator. Owns the session state machine.
// Coordinates NFCService, BLEService, and LocationService outputs.
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

    func startSession(driverTagID: String) {
        guard case .idle = state else {
            handleDriverSwitch(newTagID: driverTagID)
            return
        }

        state = .starting

        let fetchDescriptor = FetchDescriptor<Driver>(
            predicate: #Predicate { $0.nfcTagID == driverTagID }
        )

        guard let driver = try? modelContext.fetch(fetchDescriptor).first else {
            state = .idle
            return
        }

        let session = DrivingSession(driver: driver)
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

    private func handleDriverSwitch(newTagID: String) {
        guard case .active(let current) = state else { return }
        finalizeSession(current)
        startSession(driverTagID: newTagID)
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
        session.estimatedFuelLiters = FuelEstimator.estimate(session: session)

        bleService.stopMonitoring()
        locationService.stopTracking()

        try? modelContext.save()

        state = .ended
        Task {
            try? await Task.sleep(for: .seconds(1))
            state = .idle
        }
    }

    private var isStopped: Bool {
        if case .stopping = state { return true }
        return false
    }
}

// MARK: - BLEServiceDelegate

extension SessionManager: BLEServiceDelegate {
    nonisolated func bleService(_ service: BLEService, beaconPresenceChanged isPresent: Bool) {
        Task { @MainActor in
            guard case .active(let session) = self.state else {
                if !isPresent, case .stopping(let session) = self.state { return }
                return
            }
            if !isPresent {
                // BLE lost — check paired with immobility in LocationService
                // Stopping is triggered only when BOTH conditions are met.
                // Here we mark a flag; SessionManager checks both.
                self.checkTerminationConditions(session: session, blePresent: false)
            } else {
                if case .stopping(let session) = self.state {
                    self.cancelStoppingCountdown(for: session)
                }
            }
        }
    }

    private func checkTerminationConditions(session: DrivingSession, blePresent: Bool) {
        // Both beacon absence AND immobility required to enter STOPPING state
        if !blePresent && !locationService.isTracking == false {
            // Immobility is tracked inside LocationService via its delegate callback
            // This will be wired up in Week 5 with a combined condition flag
        }
        _ = session
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
            if !self.bleService.isBeaconPresent {
                self.beginStoppingCountdown(for: session)
            }
        }
    }

    private func updateSessionMetrics(session: DrivingSession, newPoint: TripPoint) {
        guard let prevPoint = session.points.dropLast().last else { return }
        let prev = CLLocation(latitude: prevPoint.latitude, longitude: prevPoint.longitude)
        let curr = CLLocation(latitude: newPoint.latitude, longitude: newPoint.longitude)
        let deltaKm = prev.distance(from: curr) / 1000.0
        session.distanceKm += deltaKm

        let deltaSpeed = newPoint.speedMps - prevPoint.speedMps
        if deltaSpeed > 2.2 { session.aggressiveAccelEvents += 1 }
        if deltaSpeed < -2.2 { session.hardBrakeEvents += 1 }
    }
}
