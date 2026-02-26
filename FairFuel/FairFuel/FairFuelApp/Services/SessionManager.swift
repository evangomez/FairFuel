import Foundation
import CoreLocation
import SwiftData

@MainActor
final class SessionManager: NSObject, ObservableObject {

    enum SessionState {
        case idle
        case starting
        case active(DrivingSession)
        case stopping(DrivingSession)
        case ended
    }

    @Published private(set) var state: SessionState = .idle
    @Published var nfcError: String?

    private let nfcService = NFCService()
    private let bleService = BLEService()
    private let locationService = LocationService()
    private var stoppingTask: Task<Void, Never>?
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        super.init()
        nfcService.delegate = self
        bleService.delegate = self
        locationService.delegate = self
    }

    // MARK: - Public API

    /// Called by UI scan button — triggers NFC read, then auto-starts session on success.
    func scanToStartSession() {
        guard case .idle = state else { return }
        nfcService.startReading()
    }

    func endSessionManually() {
        guard case .active(let session) = state else { return }
        finalizeSession(session)
    }

    /// Programs a blank NFC sticker with a vehicle's ID. Called during vehicle setup.
    func writeVehicleTag(vehicleID: String, completion: @escaping (Result<Void, Error>) -> Void) {
        nfcService.writeVehicleTag(vehicleID: vehicleID, completion: completion)
    }

    // MARK: - Private

    private func startSession(vehicleTagURI: String) {
        state = .starting

        let vehicleFetch = FetchDescriptor<Vehicle>(
            predicate: #Predicate { $0.nfcTagID == vehicleTagURI }
        )
        let driverFetch = FetchDescriptor<DriverProfile>()

        guard let vehicle = try? modelContext.fetch(vehicleFetch).first,
              let driver = try? modelContext.fetch(driverFetch).first else {
            state = .idle
            nfcError = vehicle == nil
                ? "No vehicle found for this tag. Add it in the Vehicles tab first."
                : "No driver profile found. Please set up your profile first."
            return
        }

        let session = DrivingSession(driver: driver, vehicle: vehicle)
        modelContext.insert(session)
        bleService.startMonitoring()
        locationService.startTracking()
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

// MARK: - NFCServiceDelegate

extension SessionManager: NFCServiceDelegate {
    nonisolated func nfcService(_ service: NFCService, didReadVehicleTagURI uri: String) {
        Task { @MainActor in self.startSession(vehicleTagURI: uri) }
    }

    nonisolated func nfcService(_ service: NFCService, didFailWithError error: Error) {
        Task { @MainActor in self.nfcError = error.localizedDescription }
    }
}

// MARK: - BLEServiceDelegate

extension SessionManager: BLEServiceDelegate {
    nonisolated func bleService(_ service: BLEService, beaconPresenceChanged isPresent: Bool) {
        Task { @MainActor in
            if isPresent, case .stopping(let session) = self.state {
                self.cancelStoppingCountdown(for: session)
            }
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
