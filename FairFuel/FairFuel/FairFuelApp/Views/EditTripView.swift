import SwiftUI
import SwiftData

struct EditTripView: View {
    let session: DrivingSession

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [DriverProfile]
    @Query private var vehicles: [Vehicle]

    @State private var distanceMilesText: String
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var selectedDriverID: UUID?
    @State private var selectedVehicleID: UUID?

    init(session: DrivingSession) {
        self.session = session
        _distanceMilesText = State(initialValue: String(format: "%.2f", Units.kmToMiles(session.distanceKm)))
        _startTime = State(initialValue: session.startTime)
        _endTime = State(initialValue: session.endTime ?? Date())
        _selectedDriverID = State(initialValue: session.driver?.id)
        _selectedVehicleID = State(initialValue: session.vehicle?.id)
    }

    private var distanceMiles: Double { Double(distanceMilesText) ?? 0 }

    private var selectedVehicle: Vehicle? {
        vehicles.first { $0.id == selectedVehicleID }
    }

    private var canSave: Bool {
        distanceMiles >= 0 && endTime >= startTime
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip Times") {
                    DatePicker("Start", selection: $startTime)
                    DatePicker("End", selection: $endTime)
                }

                Section("Distance") {
                    HStack {
                        TextField("0.00", text: $distanceMilesText)
                            .keyboardType(.decimalPad)
                        Text("mi").foregroundStyle(.secondary)
                    }
                }

                Section("Driver") {
                    Picker("Driver", selection: $selectedDriverID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(profiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                }

                Section("Vehicle") {
                    Picker("Vehicle", selection: $selectedVehicleID) {
                        Text("None").tag(Optional<UUID>.none)
                        ForEach(vehicles) { vehicle in
                            Text(vehicle.name).tag(Optional(vehicle.id))
                        }
                    }
                }

                if let vehicle = selectedVehicle {
                    Section {
                        LabeledContent("Efficiency") {
                            Text(Units.mpgString(vehicle.fuelEfficiencyLitersPer100Km))
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Est. Fuel after save") {
                            Text(Units.gallonsString(recalculatedFuelLiters))
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Fuel Estimate Preview")
                    }
                }
            }
            .navigationTitle("Edit Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
    }

    // Mirrors FuelEstimator.estimate but uses the edited distance + selected vehicle
    private var recalculatedFuelLiters: Double {
        let lp100km = selectedVehicle?.fuelEfficiencyLitersPer100Km ?? FuelEstimator.defaultLitersPer100Km
        guard lp100km > 0 else { return 0 }
        let distanceKm = distanceMiles * 1.60934
        let baseFuel = (distanceKm / 100.0) * lp100km
        let idleFuel = (session.idleSeconds / 3600.0) * FuelEstimator.idleFuelLitersPerHour
        let aggressiveFuel = Double(session.aggressiveAccelEvents) * FuelEstimator.aggressivePenaltyPerEvent
        let brakeFuel = Double(session.hardBrakeEvents) * FuelEstimator.hardBrakePenaltyPerEvent
        return max(0, baseFuel + idleFuel + aggressiveFuel + brakeFuel)
    }

    private func save() {
        session.startTime = startTime
        session.endTime = endTime
        session.distanceKm = distanceMiles * 1.60934
        session.driver = profiles.first { $0.id == selectedDriverID }
        session.vehicle = selectedVehicle
        session.estimatedFuelLiters = recalculatedFuelLiters
        try? modelContext.save()
        dismiss()
    }
}
