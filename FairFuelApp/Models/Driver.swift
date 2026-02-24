import Foundation
import SwiftData

@Model
final class Driver {
    var id: UUID
    var name: String
    var nfcTagID: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade)
    var sessions: [DrivingSession]

    init(name: String, nfcTagID: String) {
        self.id = UUID()
        self.name = name
        self.nfcTagID = nfcTagID
        self.createdAt = Date()
        self.sessions = []
    }
}
