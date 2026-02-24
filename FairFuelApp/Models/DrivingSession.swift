import Foundation
import SwiftData

@Model
final class DrivingSession {
    var id: UUID
    var startTime: Date
    var endTime: Date?
    var distanceKm: Double
    var idleSeconds: Double
    var aggressiveAccelEvents: Int
    var hardBrakeEvents: Int
    var estimatedFuelLiters: Double

    var driver: Driver?

    @Relationship(deleteRule: .cascade)
    var points: [TripPoint]

    var isActive: Bool { endTime == nil }

    var durationSeconds: Double {
        let end = endTime ?? Date()
        return end.timeIntervalSince(startTime)
    }

    init(driver: Driver) {
        self.id = UUID()
        self.startTime = Date()
        self.endTime = nil
        self.distanceKm = 0
        self.idleSeconds = 0
        self.aggressiveAccelEvents = 0
        self.hardBrakeEvents = 0
        self.estimatedFuelLiters = 0
        self.driver = driver
        self.points = []
    }
}
