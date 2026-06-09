import SwiftUI
import SwiftData

@main
struct FairFuelApp: App {
    let container: ModelContainer
    let sessionManager: SessionManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = Self.makeContainer()
        self.container = container
        self.sessionManager = SessionManager(modelContext: container.mainContext)
        NotificationService.shared.requestPermission()
        NotificationService.shared.registerBackgroundTask(container: container)
        // Refresh auth token on launch so background trip sync has a valid token
        Task { await AuthService.shared.refreshIfNeeded() }
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

    // Use a fixed store URL so we can apply file protection before SwiftData opens it.
    // .completeUntilFirstUserAuthentication (NOT .complete) — .complete locks the file
    // when the screen locks, which would block background GPS writes during active trips.
    private static func makeContainer() -> ModelContainer {
        let fm = FileManager.default
        let dir = URL.applicationSupportDirectory
            .appending(path: "FairFuel", directoryHint: .isDirectory)
        let storeURL = dir.appending(path: "default.store")
        let protection: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: protection)
        if fm.fileExists(atPath: storeURL.path) {
            try? fm.setAttributes(protection, ofItemAtPath: storeURL.path)
        }
        return try! ModelContainer(
            for: DriverProfile.self, Vehicle.self, DrivingSession.self, TripPoint.self, FuelEntry.self,
            configurations: ModelConfiguration(url: storeURL)
        )
    }
}
