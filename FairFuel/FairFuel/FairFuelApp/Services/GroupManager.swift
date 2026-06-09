import Foundation

final class GroupManager: ObservableObject {
    static let shared = GroupManager()

    @Published private(set) var vehicleIDs: [String] = []

    var hasGroup: Bool { !vehicleIDs.isEmpty }

    /// Compatibility shim: returns the first vehicle ID, or nil if no memberships.
    /// Do-not-touch files (AddManualTripView, AddFuelEntryView, EditVehicleView,
    /// CostSplitView, NotificationService) still reference groupID — this keeps them compiling.
    var groupID: String? { vehicleIDs.first }

    private init() {}

    /// Fetches vehicles the current user has membership for and updates vehicleIDs.
    func fetchMemberships() async {
        let vehicles = await CloudKitService.shared.fetchMemberVehicles()
        await MainActor.run {
            vehicleIDs = vehicles.map { $0.id }
        }
        print("[GroupManager] fetchMemberships — \(vehicleIDs.count) vehicle(s)")
    }

    /// Generates a server-side invite code for the given vehicleID.
    /// Returns a formatted XXXX-XXXX code on success.
    func createInvite(vehicleID: String) async -> String? {
        return await CloudKitService.shared.createInvite(vehicleID: vehicleID)
    }

    /// Redeems an invite code. Returns the vehicle name on success, nil on failure.
    func redeemInvite(code: String) async -> String? {
        guard let result = await CloudKitService.shared.redeemInvite(code: code) else { return nil }
        // Add newly joined vehicle to local list
        await MainActor.run {
            if !vehicleIDs.contains(result.vehicleID) {
                vehicleIDs.append(result.vehicleID)
            }
        }
        return result.vehicleName
    }

    /// Clears vehicle membership state (call on sign-out).
    func clearMemberships() {
        vehicleIDs = []
        print("[GroupManager] Memberships cleared")
    }
}
