import SwiftUI
import SwiftData

struct AddVehicleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var vehicleName = ""
    @State private var efficiencyText = "9.4"
    @State private var beaconUUID = ""

    private var efficiency: Double { Double(efficiencyText) ?? 9.4 }
    private var canSave: Bool {
        !vehicleName.trimmingCharacters(in: .whitespaces).isEmpty &&
        UUID(uuidString: beaconUUID.trimmingCharacters(in: .whitespaces)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle Details") {
                    TextField("Name (e.g. Honda Civic)", text: $vehicleName)
                    HStack {
                        Text("Fuel efficiency")
                        Spacer()
                        TextField("9.4", text: $efficiencyText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                        Text("L/100km")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $beaconUUID)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: beaconUUID) { _, new in
                            beaconUUID = new.uppercased()
                        }
                } header: {
                    Text("Beacon UUID")
                } footer: {
                    Text("Find this in the beacon's manufacturer app (e.g. BeaconSET for MINEW). It looks like: E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")
                }
            }
            .navigationTitle("Add Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveVehicle() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func saveVehicle() {
        let name = vehicleName.trimmingCharacters(in: .whitespaces)
        let uuid = beaconUUID.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, UUID(uuidString: uuid) != nil else { return }

        let vehicle = Vehicle(name: name, beaconUUID: uuid, fuelEfficiencyLitersPer100Km: efficiency)
        modelContext.insert(vehicle)
        try? modelContext.save()

        // start monitoring the new beacon right away
        sessionManager.beginMonitoring(vehicle: vehicle)
        dismiss()
    }
}
