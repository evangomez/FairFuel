import SwiftUI
import SwiftData

@main
struct FairFuelApp: App {
    let container: ModelContainer
    let sessionManager: SessionManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = try! ModelContainer(
            for: DriverProfile.self, Vehicle.self, DrivingSession.self, TripPoint.self, FuelEntry.self
        )
        self.container = container
        self.sessionManager = SessionManager(modelContext: container.mainContext)
        NotificationService.shared.requestPermission()
        NotificationService.shared.registerBackgroundTask(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(sessionManager)
                .environmentObject(GroupManager.shared)
                .onAppear {
                    NotificationService.shared.scheduleNextRefresh()
                    Task { await OfflineQueue.shared.drainIfNeeded() }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await OfflineQueue.shared.drainIfNeeded() }
                    }
                }
        }
        .modelContainer(container)
    }
}
