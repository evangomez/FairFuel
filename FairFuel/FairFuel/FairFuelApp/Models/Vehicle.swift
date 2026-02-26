import Foundation
import SwiftData

// A vehicle registered in the app, identified by its single NFC tag.
// One tag per vehicle, shared by all drivers — the tag encodes the vehicle, not the driver.
@Model
final class Vehicle {
    var id: UUID
    var name: String
    var nfcTagID: String                        // URI written to the tag: "fairfuel://vehicle/<UUID>"
    var fuelEfficiencyLitersPer100Km: Double    // used by FuelEstimator; user-configurable

    @Relationship(deleteRule: .nullify)
    var sessions: [DrivingSession]

    init(name: String, fuelEfficiencyLitersPer100Km: Double = 9.4) {
        self.id = UUID()
        self.name = name
        self.nfcTagID = "fairfuel://vehicle/\(UUID().uuidString)"
        self.fuelEfficiencyLitersPer100Km = fuelEfficiencyLitersPer100Km
        self.sessions = []
    }
}
