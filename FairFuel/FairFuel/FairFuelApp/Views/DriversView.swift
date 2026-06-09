import SwiftUI
import SwiftData

struct DriversView: View {
    @Query var profiles: [DriverProfile]
    @Query var vehicles: [Vehicle]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var sessionManager: SessionManager
    @ObservedObject private var groupManager = GroupManager.shared
    @State private var showAddVehicle = false
    @State private var editingVehicle: Vehicle? = nil
    @State private var showGroupSetup: GroupSetupView.Mode? = nil
    @State private var isEditingName = false
    @State private var editingNameText = ""
    @State private var groupVehicles: [RemoteVehicle] = []

    private var unadoptedGroupVehicles: [RemoteVehicle] {
        let localUUIDs = Set(vehicles.map { $0.beaconUUID.uppercased() })
        return groupVehicles.filter { !localUUIDs.contains($0.beaconUUID.uppercased()) }
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
                        Text("Group Vehicles")
                    } footer: {
                        Text("Vehicles from other group members. Tap Adopt to add to your device.")
                    }
                }

                Section("Group") {
                    if let code = groupManager.displayCode {
                        LabeledContent("Group Code") {
                            Text(code)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.semibold)
                        }
                        ShareLink(item: "Join my FairFuel group! Code: \(code)") {
                            Label("Share Code", systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            groupManager.leaveGroup()
                        } label: {
                            Label("Leave Group", systemImage: "person.badge.minus")
                        }
                    } else {
                        Button {
                            showGroupSetup = .create
                        } label: {
                            Label("Create Group", systemImage: "person.badge.plus")
                        }
                        Button {
                            showGroupSetup = .join
                        } label: {
                            Label("Join Group", systemImage: "person.2")
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
            .task(id: groupManager.groupID) {
                guard let groupID = groupManager.groupID else {
                    groupVehicles = []
                    return
                }
                // Push all local vehicles so devices that joined before adding vehicles still sync
                for vehicle in vehicles {
                    await CloudKitService.shared.pushVehicle(vehicle, groupID: groupID)
                }
                groupVehicles = await CloudKitService.shared.fetchVehicles(groupID: groupID)
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
        groupVehicles.removeAll { $0.id == remote.id }
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
    public var id: Int {
        switch self {
        case .create: return 0
        case .join: return 1
        }
    }
}
