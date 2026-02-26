import SwiftUI
import SwiftData

struct DriversView: View {
    @Query var profiles: [DriverProfile]
    @Query var vehicles: [Vehicle]
    @Environment(\.modelContext) private var modelContext
    @State private var showAddVehicle = false

    var body: some View {
        NavigationStack {
            List {
                Section("My Profile") {
                    if let profile = profiles.first {
                        LabeledContent(profile.name) {
                            Text("\(profile.sessions.count) trips")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Vehicles") {
                    ForEach(vehicles) { vehicle in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(vehicle.name).font(.headline)
                            Text(String(format: "%.1f L/100km", vehicle.fuelEfficiencyLitersPer100Km))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteVehicles)

                    Button {
                        showAddVehicle = true
                    } label: {
                        Label("Add Vehicle", systemImage: "plus.circle")
                    }
                }
            }
            .navigationTitle("Profile & Vehicles")
            .sheet(isPresented: $showAddVehicle) {
                AddVehicleView()
            }
        }
    }

    private func deleteVehicles(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(vehicles[index]) }
        try? modelContext.save()
    }
}
