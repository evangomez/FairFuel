import SwiftUI
import SwiftData

struct FuelView: View {
    @Query(sort: \FuelEntry.date, order: .reverse) var entries: [FuelEntry]
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var groupManager = GroupManager.shared
    @State private var showAddEntry = false

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "No Fuel Entries",
                        systemImage: "fuelpump",
                        description: Text("Log a fill-up to see cost splits.")
                    )
                } else {
                    List {
                        Section {
                            CurrentTankCard(entry: entries[0], vehicleIDs: groupManager.vehicleIDs)
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }

                        Section("Fill-up History") {
                            ForEach(entries) { entry in
                                NavigationLink(destination: CostSplitView(entry: entry)) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                                .font(.subheadline).bold()
                                            Spacer()
                                            if entry.isSettled {
                                                Label("Settled", systemImage: "checkmark.circle.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.green)
                                            }
                                        }
                                        HStack(spacing: 16) {
                                            Text(String(format: "%.3f gal", Units.litersToGallons(entry.liters)))
                                                .foregroundStyle(.secondary)
                                            Text(String(format: "$%.2f", entry.totalCost))
                                                .foregroundStyle(.secondary)
                                            Text(Units.perGallonString(costPerLiter: entry.costPerLiter))
                                                .foregroundStyle(.secondary)
                                        }
                                        .font(.caption)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Fuel")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAddEntry = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddEntry) {
                AddFuelEntryView()
            }
            .task(id: groupManager.vehicleIDs.description) {
                let vehicleIDs = groupManager.vehicleIDs
                guard !vehicleIDs.isEmpty else { return }
                // Push local entries to the server for each vehicle this user owns
                for entry in entries {
                    // Only push entries where we know the vehicle — use first owned vehicle as fallback
                    if let firstVehicleID = vehicleIDs.first {
                        await CloudKitService.shared.pushFuelEntry(entry, vehicleID: firstVehicleID)
                    }
                }
                let remote = await CloudKitService.shared.fetchFuelEntries(vehicleIDs: vehicleIDs)
                var changed = false
                for r in remote {
                    if let existing = entries.first(where: { $0.id.uuidString == r.id }) {
                        if existing.isSettled != r.isSettled {
                            existing.isSettled = r.isSettled
                            changed = true
                        }
                    } else {
                        guard let uuid = UUID(uuidString: r.id) else { continue }
                        let entry = FuelEntry(id: uuid, date: r.date, liters: r.liters,
                                             totalCost: r.totalCost, odometer: r.odometer)
                        entry.isSettled = r.isSettled
                        modelContext.insert(entry)
                        changed = true
                    }
                }
                if changed { try? modelContext.save() }
            }
        }
    }
}

// MARK: - Current Tank Card

private struct CurrentTankCard: View {
    let entry: FuelEntry
    let vehicleIDs: [String]

    @Query(sort: \DrivingSession.startTime) private var allSessions: [DrivingSession]
    @State private var showGaugeInput = false
    @State private var gaugeText = ""
    @State private var remoteSessions: [RemoteSession] = []
    @State private var isLoadingRemote = false
    @FocusState private var gaugeFieldFocused: Bool

    private var localSessions: [DrivingSession] {
        allSessions.filter { $0.endTime != nil && $0.startTime >= entry.date }
    }

    private var usingRemote: Bool { !remoteSessions.isEmpty }

    private var gaugePercent: Double? {
        guard let v = Double(gaugeText), v >= 0, v <= 100 else { return nil }
        return v
    }

    private var totalSessionFuelLiters: Double {
        if usingRemote {
            return remoteSessions.reduce(0) { $0 + $1.estimatedFuelLiters }
        }
        return localSessions.reduce(0) { $0 + $1.estimatedFuelLiters }
    }

    // With gauge: scale the actual fill-up cost by how much has been used.
    // Without gauge: multiply session fuel estimates by last known price per liter.
    private var estimatedCostUsed: Double {
        if let pct = gaugePercent {
            return entry.totalCost * (1.0 - pct / 100.0)
        }
        return totalSessionFuelLiters * entry.costPerLiter
    }

    private var breakdown: [(name: String, cost: Double)] {
        guard totalSessionFuelLiters > 0 else { return [] }
        var byDriver: [String: Double] = [:]
        if usingRemote {
            for session in remoteSessions {
                byDriver[session.driverName, default: 0] += session.estimatedFuelLiters
            }
        } else {
            for session in localSessions {
                let name = session.driver?.name ?? "Unknown"
                byDriver[name, default: 0] += session.estimatedFuelLiters
            }
        }
        return byDriver.map { (name: $0.key, cost: ($0.value / totalSessionFuelLiters) * estimatedCostUsed) }
            .sorted { $0.cost > $1.cost }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current Tank")
                        .font(.headline)
                    Text("Since \(entry.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "$%.2f", estimatedCostUsed))
                        .font(.title3).bold()
                    Text("est. used")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if isLoadingRemote {
                HStack {
                    ProgressView()
                    Text("Syncing…")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .padding(.leading, 8)
                }
            } else if breakdown.isEmpty {
                Text("No trips recorded since this fill-up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(breakdown, id: \.name) { row in
                    HStack {
                        Text(row.name)
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "$%.2f", row.cost))
                            .font(.subheadline).bold()
                    }
                }
                if usingRemote {
                    Label("Includes trips from all vehicle members", systemImage: "icloud")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                showGaugeInput.toggle()
                if showGaugeInput {
                    gaugeFieldFocused = true
                } else {
                    gaugeText = ""
                    gaugeFieldFocused = false
                }
            } label: {
                Label(showGaugeInput ? "Remove gauge input" : "Refine with fuel gauge",
                      systemImage: "gauge.medium")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if showGaugeInput {
                HStack {
                    Text("Tank remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    TextField("e.g. 50", text: $gaugeText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 55)
                        .font(.caption)
                        .focused($gaugeFieldFocused)
                    Text("%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Done") { gaugeFieldFocused = false }
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                        .padding(.leading, 6)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .task(id: vehicleIDs.description) {
            await fetchRemoteSessions()
        }
    }

    private func fetchRemoteSessions() async {
        guard !vehicleIDs.isEmpty else {
            remoteSessions = []
            return
        }
        isLoadingRemote = true
        let fetched = await CloudKitService.shared.fetchTrips(
            vehicleIDs: vehicleIDs,
            since: entry.date,
            until: Date()
        )
        isLoadingRemote = false
        remoteSessions = fetched.sorted { $0.startTime > $1.startTime }
    }
}
