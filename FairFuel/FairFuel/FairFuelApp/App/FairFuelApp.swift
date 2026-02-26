import SwiftUI
import SwiftData

@main
struct FairFuelApp: App {
    let container: ModelContainer
    let sessionManager: SessionManager

    init() {
        let container = try! ModelContainer(
            for: DriverProfile.self, Vehicle.self, DrivingSession.self, TripPoint.self, FuelEntry.self
        )
        self.container = container
        self.sessionManager = SessionManager(modelContext: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionManager)
        }
        .modelContainer(container)
    }
}
