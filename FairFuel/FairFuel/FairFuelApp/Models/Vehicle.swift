import Foundation
import SwiftData

@Model
final class Vehicle {
    var id: UUID
    var name: String
    var beaconUUID: String                      // iBeacon UUID from the physical beacon in the car
    var fuelEfficiencyLitersPer100Km: Double

    // Optional fields added for make/model/year lookup (lightweight migration safe)
    var year: Int?
    var make: String?
    var vehicleModel: String?

    @Relationship(deleteRule: .nullify)
    var sessions: [DrivingSession]

    init(name: String, beaconUUID: String, fuelEfficiencyLitersPer100Km: Double = 9.4) {
        self.id = UUID()
        self.name = name
        self.beaconUUID = beaconUUID
        self.fuelEfficiencyLitersPer100Km = fuelEfficiencyLitersPer100Km
        self.sessions = []
    }
}
