import SwiftUI
import SwiftData

@main
struct FairFuelApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Driver.self, DrivingSession.self, TripPoint.self, FuelEntry.self])
    }
}
