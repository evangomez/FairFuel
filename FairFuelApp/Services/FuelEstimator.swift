import Foundation

// Placeholder fuel estimation model.
// Week 6 will replace this with a behavior-weighted formula.
enum FuelEstimator {

    // Default assumed fuel efficiency if no vehicle profile is set.
    // Units: liters per 100 km
    static let defaultLitersPer100Km: Double = 9.4

    // Penalty multipliers applied to the base distance consumption
    static let idleFuelLitersPerHour: Double = 0.8    // avg idle consumption
    static let aggressivePenaltyPerEvent: Double = 0.02

    static func estimate(session: DrivingSession) -> Double {
        let baseFuel = (session.distanceKm / 100.0) * defaultLitersPer100Km
        let idleHours = session.idleSeconds / 3600.0
        let idleFuel = idleHours * idleFuelLitersPerHour
        let aggressiveFuel = Double(session.aggressiveAccelEvents) * aggressivePenaltyPerEvent
        return baseFuel + idleFuel + aggressiveFuel
    }

    // Proportionally allocate a fuel entry cost across sessions since last fill-up
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
