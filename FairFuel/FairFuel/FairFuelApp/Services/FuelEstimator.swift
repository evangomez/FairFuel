import Foundation

enum FuelEstimator {
    static let defaultLitersPer100Km: Double = 9.4
    static let idleFuelLitersPerHour: Double = 0.8
    static let aggressivePenaltyPerEvent: Double = 0.02

    static func estimate(session: DrivingSession, litersPer100Km: Double = defaultLitersPer100Km) -> Double {
        let baseFuel = (session.distanceKm / 100.0) * litersPer100Km
        let idleHours = session.idleSeconds / 3600.0
        let idleFuel = idleHours * idleFuelLitersPerHour
        let aggressiveFuel = Double(session.aggressiveAccelEvents) * aggressivePenaltyPerEvent
        return baseFuel + idleFuel + aggressiveFuel
    }

    // Allocates a fuel entry's cost across sessions proportionally by estimated consumption
    static func allocateCost(fuelEntry: FuelEntry, sessions: [DrivingSession]) -> [UUID: Double] {
        let totalEstimated = sessions.reduce(0) { $0 + $1.estimatedFuelLiters }
        guard totalEstimated > 0 else { return [:] }

        var allocation: [UUID: Double] = [:]
        for session in sessions {
            guard let driverID = session.driver?.id else { continue }
            let share = session.estimatedFuelLiters / totalEstimated
            allocation[driverID, default: 0] += share * fuelEntry.totalCost
        }
        return allocation
    }
}
