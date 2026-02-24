import SwiftUI
import SwiftData

// Shows this device's driver profile and registered vehicles.
// Full implementation in Week 3.
struct DriversView: View {
    @Query var profiles: [DriverProfile]
    @Query var vehicles: [Vehicle]

    var body: some View {
        NavigationStack {
            List {
                Section("My Profile") {
                    if let profile = profiles.first {
                        VStack(alignment: .leading) {
                            Text(profile.name).font(.headline)
                            Text("\(profile.sessions.count) sessions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No profile set up yet.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Vehicles") {
                    if vehicles.isEmpty {
                        Text("No vehicles registered.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(vehicles) { vehicle in
                            VStack(alignment: .leading) {
                                Text(vehicle.name).font(.headline)
                                Text(String(format: "%.1f L/100km", vehicle.fuelEfficiencyLitersPer100Km))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Profile & Vehicles")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // Week 3: add vehicle / edit profile flow
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}
