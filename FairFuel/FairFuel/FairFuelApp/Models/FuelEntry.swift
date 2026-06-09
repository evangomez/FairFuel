import Foundation
import SwiftData

@Model
final class FuelEntry {
    var id: UUID
    var date: Date
    var liters: Double
    var totalCost: Double
    var odometer: Double?
    var isSettled: Bool = false

    var costPerLiter: Double {
        guard liters > 0 else { return 0 }
        return totalCost / liters
    }

    init(liters: Double, totalCost: Double, odometer: Double? = nil) {
        self.id = UUID()
        self.date = Date()
        self.liters = liters
        self.totalCost = totalCost
        self.odometer = odometer
    }

    init(id: UUID, date: Date, liters: Double, totalCost: Double, odometer: Double?) {
        self.id = id
        self.date = date
        self.liters = liters
        self.totalCost = totalCost
        self.odometer = odometer
    }
}
