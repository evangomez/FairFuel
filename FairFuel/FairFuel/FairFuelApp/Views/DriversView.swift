import SwiftUI
import SwiftData

struct DriversView: View {
    @Query var profiles: [DriverProfile]
    @Query var vehicles: [Vehicle]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionManager: SessionManager
    @ObservedObject private var groupManager = GroupManager.shared
    @ObservedObject private var authService = AuthService.shared
    @State private var showAddVehicle = false
    @State private var editingVehicle: Vehicle? = nil
    @State private var showGroupSetup: GroupSetupView.Mode? = nil
    @State private var isEditingName = false
    @State private var editingNameText = ""
    @State private var memberVehicles: [RemoteVehicle] = []

    /// Vehicles the user has server-side membership for but hasn't adopted locally yet.
    private var unadoptedGroupVehicles: [RemoteVehicle] {
        let localIDs = Set(vehicles.map { $0.id.uuidString.lowercased() })
        return memberVehicles.filter { !localIDs.contains($0.id.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("My Profile") {
                    if let profile = profiles.first {
                        if isEditingName {
                            HStack {
                                TextField("Your name", text: $editingNameText)
                                    .submitLabel(.done)
                                    .onSubmit { saveName(profile: profile) }
                                Button("Save") { saveName(profile: profile) }
                                    .disabled(editingNameText.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        } else {
                            NavigationLink(destination: TripHistoryView()) {
                                LabeledContent(profile.name) {
                                    Text("\(profile.sessions.filter { $0.endTime != nil }.count) trips")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button("Rename") {
                                    editingNameText = profile.name
                                    isEditingName = true
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }

                Section("Vehicles") {
                    ForEach(vehicles) { vehicle in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(vehicle.name).font(.headline)
                                Text(vehicle.beaconUUID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Circle()
                                .fill(sessionManager.detectedBeaconUUIDs.contains(vehicle.beaconUUID)
                                      ? Color.green : Color.gray.opacity(0.3))
                                .frame(width: 10, height: 10)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Invite") {
                                showGroupSetup = .create(vehicleID: vehicle.id.uuidString, vehicleName: vehicle.name)
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Edit") { editingVehicle = vehicle }
                                .tint(.blue)
                        }
                    }
                    .onDelete(perform: deleteVehicles)

                    Button {
                        showAddVehicle = true
                    } label: {
                        Label("Add Vehicle", systemImage: "plus.circle")
                    }
                }

                if !unadoptedGroupVehicles.isEmpty {
                    Section {
                        ForEach(unadoptedGroupVehicles, id: \.id) { remote in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(remote.name).font(.headline)
                                    Text(remote.beaconUUID)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    if remote.fuelEfficiencyLitersPer100Km > 0 {
                                        Text(Units.mpgString(remote.fuelEfficiencyLitersPer100Km))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button("Adopt") { adoptGroupVehicle(remote) }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text("Shared Vehicles")
                    } footer: {
                        Text("Vehicles you have membership for. Tap Adopt to add to your device for beacon detection.")
                    }
                }

                Section("Sharing") {
                    if groupManager.hasGroup {
                        LabeledContent("Member of") {
                            Text("\(groupManager.vehicleIDs.count) vehicle(s)")
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            showGroupSetup = .join
                        } label: {
                            Label("Join Another Vehicle", systemImage: "person.2")
                        }
                    } else {
                        Button {
                            showGroupSetup = .join
                        } label: {
                            Label("Join a Vehicle", systemImage: "person.2")
                        }
                    }
                }
            }
            .navigationTitle("Profile & Vehicles")
            .sheet(isPresented: $showAddVehicle) {
                AddVehicleView()
            }
            .sheet(item: $editingVehicle) { vehicle in
                EditVehicleView(vehicle: vehicle)
            }
            .sheet(item: $showGroupSetup) { mode in
                GroupSetupView(mode: mode)
            }
            .task(id: groupManager.vehicleIDs.description) {
                guard authService.isAuthenticated else { return }
                // Push all local vehicles to server and refresh memberships
                for vehicle in vehicles {
                    await CloudKitService.shared.pushVehicle(vehicle)
                }
                await GroupManager.shared.fetchMemberships()
                // Fetch all member vehicles for the unadopted section
                memberVehicles = await CloudKitService.shared.fetchMemberVehicles()
            }
        }
    }

    private func saveName(profile: DriverProfile) {
        let trimmed = editingNameText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        profile.name = trimmed
        try? modelContext.save()
        isEditingName = false
    }

    private func adoptGroupVehicle(_ remote: RemoteVehicle) {
        let vehicle = Vehicle(name: remote.name, beaconUUID: remote.beaconUUID,
                              fuelEfficiencyLitersPer100Km: remote.fuelEfficiencyLitersPer100Km)
        vehicle.make = remote.make
        vehicle.vehicleModel = remote.model
        vehicle.year = remote.year
        modelContext.insert(vehicle)
        try? modelContext.save()
        sessionManager.beginMonitoring(vehicle: vehicle)
        memberVehicles.removeAll { $0.id == remote.id }
    }

    private func deleteVehicles(at offsets: IndexSet) {
        for index in offsets {
            sessionManager.stopMonitoring(vehicle: vehicles[index])
            modelContext.delete(vehicles[index])
        }
        try? modelContext.save()
    }
}

extension GroupSetupView.Mode: Identifiable {
    public var id: String {
        switch self {
        case .create(let vehicleID, _): return "create-\(vehicleID)"
        case .join: return "join"
        }
    }
}
