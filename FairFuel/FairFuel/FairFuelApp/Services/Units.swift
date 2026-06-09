import Foundation

enum Units {
    // MARK: - Distance
    static func kmToMiles(_ km: Double) -> Double { km * 0.621371 }

    // MARK: - Fuel Volume
    static func litersToGallons(_ liters: Double) -> Double { liters * 0.264172 }
    static func gallonsToLiters(_ gallons: Double) -> Double { gallons * 3.78541 }

    // MARK: - Fuel Efficiency
    /// MPG → L/100km for internal storage
    static func mpgToLitersPer100Km(_ mpg: Double) -> Double {
        guard mpg > 0 else { return 0 }
        return 235.214 / mpg
    }

    /// L/100km → MPG for display
    static func litersPer100KmToMPG(_ lp100km: Double) -> Double {
        guard lp100km > 0 else { return 0 }
        return 235.214 / lp100km
    }

    // MARK: - Formatted Strings
    static func milesString(_ km: Double) -> String {
        String(format: "%.1f mi", kmToMiles(km))
    }

    static func gallonsString(_ liters: Double) -> String {
        String(format: "%.3f gal", litersToGallons(liters))
    }

    static func mpgString(_ lp100km: Double) -> String {
        guard lp100km > 0 else { return "Electric" }
        return String(format: "%.0f MPG", litersPer100KmToMPG(lp100km))
    }

    /// Cost per liter → formatted cost per gallon string
    static func perGallonString(costPerLiter: Double) -> String {
        String(format: "$%.3f/gal", costPerLiter * 3.78541)
    }
}
