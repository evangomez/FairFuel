import SwiftUI
import SwiftData

struct CostSplitView: View {
    let entry: FuelEntry

    @Environment(\.modelContext) private var modelContext
    @State private var breakdown: [(name: String, cost: Double)] = []
    @State private var includedSessions: [DrivingSession] = []
    @State private var remoteSessions: [RemoteSession] = []
    @State private var isLoadingRemote = false
    @State private var computedEfficiencyMPG: Double? = nil

    private var usingRemote: Bool { !remoteSessions.isEmpty }

    var body: some View {
        List {
            Section("Fill-up") {
                LabeledContent("Date") {
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Volume") {
                    Text(String(format: "%.3f gal", Units.litersToGallons(entry.liters)))
                }
                LabeledContent("Total Cost") {
                    Text(String(format: "$%.2f", entry.totalCost))
                }
                LabeledContent("Price per Gallon") {
                    Text(Units.perGallonString(costPerLiter: entry.costPerLiter))
                }
                if let odo = entry.odometer {
                    LabeledContent("Odometer") {
                        Text(String(format: "%.0f mi", Units.kmToMiles(odo)))
                    }
                }
                if let mpg = computedEfficiencyMPG {
                    LabeledContent("Actual Efficiency") {
                        Text(String(format: "%.0f MPG", mpg))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Cost Breakdown") {
                if isLoadingRemote {
                    HStack {
                        ProgressView()
                        Text("Syncing…")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                            .padding(.leading, 8)
                    }
                } else if breakdown.isEmpty {
                    Text("No sessions recorded since the last fill-up.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(breakdown, id: \.name) { row in
                        HStack {
                            Text(row.name)
                            Spacer()
                            Text(String(format: "$%.2f", row.cost))
                                .foregroundStyle(.primary)
                                .bold()
                        }
                    }
                    if usingRemote {
                        Label("Includes trips from all group members", systemImage: "icloud")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Settlement") {
                if entry.isSettled {
                    Label("Settled", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Mark as Unsettled") {
                        Task { await toggleSettled() }
                    }
                    .foregroundStyle(.red)
                } else {
                    Label("Outstanding", systemImage: "clock")
                        .foregroundStyle(.secondary)
                    Button("Mark as Settled") {
                        Task { await toggleSettled() }
                    }
                }
            }

            if usingRemote {
                Section("Included Trips (\(remoteSessions.count))") {
                    ForEach(remoteSessions, id: \.recordName) { session in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(session.driverName)
                                    .font(.subheadline)
                                Spacer()
                                Text(Units.milesString(session.distanceKm))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Text(session.startTime.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("~\(Units.gallonsString(session.estimatedFuelLiters))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else if !includedSessions.isEmpty {
                Section("Included Trips (\(includedSessions.count))") {
                    ForEach(includedSessions) { session in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(session.driver?.name ?? "Unknown")
                                    .font(.subheadline)
                                Spacer()
                                Text(Units.milesString(session.distanceKm))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            HStack {
                                Text(session.startTime.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("~\(Units.gallonsString(session.estimatedFuelLiters))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Cost Split")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            Task { await loadBreakdown() }
        }
    }

    private func toggleSettled() async {
        entry.isSettled.toggle()
        try? modelContext.save()
        if let groupID = GroupManager.shared.groupID {
            await CloudKitService.shared.updateSettled(
                entryID: entry.id.uuidString, groupID: groupID, isSettled: entry.isSettled)
        }
    }

    private func loadBreakdown() async {
        let allEntries = (try? modelContext.fetch(
            FetchDescriptor<FuelEntry>(sortBy: [SortDescriptor(\.date)])
        )) ?? []

        // Window: from THIS fill-up until the NEXT one (or now if most recent)
        let sinceDate = entry.date
        let untilDate: Date
        if let idx = allEntries.firstIndex(where: { $0.id == entry.id }),
           idx < allEntries.count - 1 {
            untilDate = allEntries[idx + 1].date
        } else {
            untilDate = Date()
        }

        // Compute actual fuel efficiency from consecutive odometer readings
        if let newOdo = entry.odometer,
           let prevEntry = allEntries.last(where: { $0.id != entry.id && $0.date < entry.date && $0.odometer != nil }),
           let prevOdo = prevEntry.odometer, newOdo > prevOdo {
            let distKm = newOdo - prevOdo
            if distKm > 0 {
                let lp100km = entry.liters / (distKm / 100.0)
                computedEfficiencyMPG = Units.litersPer100KmToMPG(lp100km)
                // Auto-update the vehicle's efficiency if only one vehicle is saved
                let vehicles = (try? modelContext.fetch(FetchDescriptor<Vehicle>())) ?? []
                if vehicles.count == 1 {
                    vehicles[0].fuelEfficiencyLitersPer100Km = lp100km
                    try? modelContext.save()
                }
            }
        }

        if let groupID = GroupManager.shared.groupID {
            isLoadingRemote = true
            let fetched = await CloudKitService.shared.fetchSessions(
                groupID: groupID,
                since: sinceDate,
                until: untilDate
            )
            isLoadingRemote = false

            if !fetched.isEmpty {
                remoteSessions = fetched.sorted { $0.startTime > $1.startTime }
                let allocation = FuelEstimator.allocateCost(totalCost: entry.totalCost, sessions: fetched)
                breakdown = allocation
                    .map { (name: $0.key, cost: $0.value) }
                    .sorted { $0.cost > $1.cost }
                return
            }
        }

        let allSessions = (try? modelContext.fetch(FetchDescriptor<DrivingSession>())) ?? []
        let relevant = allSessions.filter {
            $0.endTime != nil &&
            $0.startTime >= sinceDate &&
            $0.startTime <= untilDate
        }
        includedSessions = relevant.sorted { $0.startTime > $1.startTime }

        let allocation = FuelEstimator.allocateCost(fuelEntry: entry, sessions: relevant)
        let profiles = (try? modelContext.fetch(FetchDescriptor<DriverProfile>())) ?? []
        let nameMap = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.name) })
        breakdown = allocation
            .map { (name: nameMap[$0.key] ?? "Unknown", cost: $0.value) }
            .sorted { $0.cost > $1.cost }
    }
}
