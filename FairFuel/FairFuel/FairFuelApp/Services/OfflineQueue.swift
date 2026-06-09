import Foundation

// Persists failed Supabase upserts so they can be retried when connectivity returns.
final class OfflineQueue {
    static let shared = OfflineQueue()
    private let key = "supabaseOfflineQueue"
    private init() {}

    struct PendingUpsert: Codable {
        let table: String
        let bodyJSON: Data
    }

    private func load() -> [PendingUpsert] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([PendingUpsert].self, from: data)
        else { return [] }
        return items
    }

    private func save(_ items: [PendingUpsert]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: key)
    }

    func enqueue(table: String, bodyData: Data) {
        var queue = load()
        queue.append(PendingUpsert(table: table, bodyJSON: bodyData))
        save(queue)
        print("[OfflineQueue] Queued 1 upsert for \(table) — queue size: \(queue.count)")
    }

    var isEmpty: Bool { load().isEmpty }

    func drainIfNeeded() async {
        let queue = load()
        guard !queue.isEmpty else { return }
        print("[OfflineQueue] Draining \(queue.count) pending upserts…")
        var remaining: [PendingUpsert] = []
        for item in queue {
            let ok = await CloudKitService.shared.upsertRaw(table: item.table, bodyData: item.bodyJSON)
            if !ok { remaining.append(item) }
        }
        save(remaining)
        let drained = queue.count - remaining.count
        print("[OfflineQueue] Drained \(drained), \(remaining.count) still pending")
    }
}
