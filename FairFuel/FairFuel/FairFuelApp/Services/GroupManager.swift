import Foundation

final class GroupManager: ObservableObject {
    static let shared = GroupManager()

    private let key = "groupID"

    @Published private(set) var groupID: String?

    var displayCode: String? {
        guard let id = groupID, id.count == 8 else { return groupID }
        return "\(id.prefix(4))-\(id.suffix(4))"
    }

    private init() {
        groupID = UserDefaults.standard.string(forKey: key)
    }

    func createGroup() {
        // Excludes 0/O, 1/I/L to prevent mix-ups when sharing codes
        let chars = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        let id = String((0..<8).map { _ in chars.randomElement()! })
        store(id)
    }

    /// Returns `true` if the code was valid and stored.
    func join(code: String) -> Bool {
        let clean = code.uppercased().replacingOccurrences(of: "-", with: "")
        guard clean.count == 8, clean.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            return false
        }
        store(clean)
        return true
    }

    func leaveGroup() {
        UserDefaults.standard.removeObject(forKey: key)
        groupID = nil
    }

    private func store(_ id: String) {
        UserDefaults.standard.set(id, forKey: key)
        groupID = id
    }
}
