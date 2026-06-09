import SwiftUI
import SwiftData

struct AddManualTripView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var vehicles: [Vehicle]
    @Query private var profiles: [DriverProfile]

    @State private var distanceMilesText = ""
    @State private var durationMinutesText = ""
    @State private var date = Date()
    @State private var selectedVehicle: Vehicle?

    private var isValid: Bool {
        guard let d = Double(distanceMilesText) else { return false }
        return d > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Trip Details") {
                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    HStack {
                        Text("Distance")
                        Spacer()
                        TextField("0.0", text: $distanceMilesText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("mi").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Duration")
                        Spacer()
                        TextField("Optional", text: $durationMinutesText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("min").foregroundStyle(.secondary)
                    }
                }
                if !vehicles.isEmpty {
                    Section("Vehicle") {
                        Picker("Vehicle", selection: $selectedVehicle) {
                            Text("None").tag(Optional<Vehicle>.none)
                            ForEach(vehicles) { v in
                                Text(v.name).tag(Optional(v))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Manual Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .onAppear { selectedVehicle = vehicles.first }
        }
    }

    private func save() {
        guard let driver = profiles.first,
              let distanceMiles = Double(distanceMilesText) else { return }
        let distanceKm = distanceMiles * 1.60934
        let durationSecs = (Double(durationMinutesText) ?? 0) * 60
        let vehicle = selectedVehicle
        let efficiency = vehicle?.fuelEfficiencyLitersPer100Km ?? FuelEstimator.defaultLitersPer100Km

        let session = DrivingSession(driver: driver, vehicle: vehicle, isManual: true)
        session.startTime = date
        session.endTime = date.addingTimeInterval(max(durationSecs, 60))
        session.distanceKm = distanceKm
        session.estimatedFuelLiters = (distanceKm / 100.0) * efficiency

        modelContext.insert(session)
        try? modelContext.save()

        if let groupID = GroupManager.shared.groupID {
            Task { await CloudKitService.shared.pushSession(session, groupID: groupID) }
        }
        dismiss()
    }
}
