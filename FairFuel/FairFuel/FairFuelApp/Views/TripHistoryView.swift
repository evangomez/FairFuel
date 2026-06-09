import SwiftUI
import SwiftData

struct TripHistoryView: View {
    @Query(sort: \DrivingSession.startTime, order: .reverse) private var allSessions: [DrivingSession]
    @Environment(\.modelContext) private var modelContext
    @State private var editingSession: DrivingSession? = nil
    @State private var showManualTrip = false

    private var sessions: [DrivingSession] {
        allSessions.filter { $0.endTime != nil }
    }

    var body: some View {
        Group {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No Trips Yet",
                    systemImage: "car.circle",
                    description: Text("Completed trips will appear here.")
                )
            } else {
                List {
                    ForEach(sessions) { session in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline).bold()
                                if session.isManual {
                                    Text("Manual")
                                        .font(.caption2)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15))
                                        .foregroundStyle(.orange)
                                        .clipShape(Capsule())
                                }
                                Spacer()
                                if let vehicle = session.vehicle {
                                    Text(vehicle.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            HStack(spacing: 20) {
                                statLabel(value: Units.milesString(session.distanceKm), label: "Distance")
                                statLabel(value: formatDuration(session.durationSeconds), label: "Duration")
                                statLabel(value: Units.gallonsString(session.estimatedFuelLiters), label: "Est. Fuel")
                            }

                            if session.aggressiveAccelEvents > 0 || session.hardBrakeEvents > 0 {
                                HStack(spacing: 12) {
                                    if session.aggressiveAccelEvents > 0 {
                                        Label("\(session.aggressiveAccelEvents) hard accel", systemImage: "arrow.up.right")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }
                                    if session.hardBrakeEvents > 0 {
                                        Label("\(session.hardBrakeEvents) hard brake", systemImage: "arrow.down.right")
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .leading) {
                            Button("Edit") { editingSession = session }
                                .tint(.blue)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) { deleteSession(session) }
                        }
                    }
                }
            }
        }
        .navigationTitle("Trip History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showManualTrip = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editingSession) { session in
            EditTripView(session: session)
        }
        .sheet(isPresented: $showManualTrip) {
            AddManualTripView()
        }
    }

    private func deleteSession(_ session: DrivingSession) {
        modelContext.delete(session)
        try? modelContext.save()
    }

    private func statLabel(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.caption).bold()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
