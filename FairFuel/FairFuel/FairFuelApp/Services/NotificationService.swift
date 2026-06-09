import Foundation
import UserNotifications
import BackgroundTasks
import SwiftData

final class NotificationService {
    static let shared = NotificationService()
    static let bgTaskID = "com.fairfuel.refresh"
    private init() {}

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            print("[Notifications] Permission granted: \(granted)")
        }
    }

    // Must be called in App.init() before the app finishes launching.
    func registerBackgroundTask(container: ModelContainer) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.bgTaskID, using: nil) { task in
            task.expirationHandler = { task.setTaskCompleted(success: false) }
            Task {
                await self.runRefresh(container: container)
                await OfflineQueue.shared.drainIfNeeded()
                task.setTaskCompleted(success: true)
                self.scheduleNextRefresh()
            }
        }
    }

    func scheduleNextRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: Self.bgTaskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(req)
    }

    private func runRefresh(container: ModelContainer) async {
        guard let groupID = GroupManager.shared.groupID else { return }
        let remote = await CloudKitService.shared.fetchFillUps(groupID: groupID)
        let context = ModelContext(container)
        let localIDs = Set(((try? context.fetch(FetchDescriptor<FuelEntry>())) ?? []).map { $0.id.uuidString })
        let newCount = remote.filter { !localIDs.contains($0.id) }.count
        if newCount > 0 { postRefuelNotification(count: newCount) }
    }

    func postRefuelNotification(count: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Group Refueled"
        content.body = count == 1
            ? "A group member logged a fill-up — costs updated."
            : "\(count) new fill-ups in your group — costs updated."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }
}
