import SwiftUI
import SwiftData

@main
struct FairFuelApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [DriverProfile.self, Vehicle.self, DrivingSession.self, TripPoint.self, FuelEntry.self])
    }
}
