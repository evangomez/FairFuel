import Foundation

extension Double {
    var kmToMiles: Double { self * 0.621371 }

    var distanceDisplay: String {
        String(format: "%.1f mi", kmToMiles)
    }

    var fuelDisplay: String {
        String(format: "%.3f gal", self * 0.264172)
    }
}
