import Foundation
import SwiftData

// The local driver profile stored on this device.
// There is exactly one DriverProfile per phone — the phone's owner.
// Driver identity comes from the device, not from the NFC tag.
@Model
final class DriverProfile {
    var id: UUID
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade)
    var sessions: [DrivingSession]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.sessions = []
    }
}
