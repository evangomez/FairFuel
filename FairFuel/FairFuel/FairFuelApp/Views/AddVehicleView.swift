import SwiftUI
import SwiftData

struct AddVehicleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var selectedMake = ""
    @State private var selectedModel = ""
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var customName = ""
    @State private var useCustomName = false
    @State private var mpgText = ""
    @State private var beaconUUID = ""

    private static let yearRange = Array((2000...Calendar.current.component(.year, from: Date())).reversed())

    private var availableModels: [String] { VehicleDatabase.models(for: selectedMake) }

    private var autoName: String {
        guard !selectedMake.isEmpty else { return "" }
        let model = selectedModel.isEmpty ? "" : " \(selectedModel)"
        return "\(selectedYear) \(selectedMake)\(model)"
    }

    private var displayName: String {
        useCustomName ? customName : autoName
    }

    private var mpg: Double { Double(mpgText) ?? 0 }
    private var isElectric: Bool { !mpgText.isEmpty && mpg == 0 }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty &&
        UUID(uuidString: beaconUUID.trimmingCharacters(in: .whitespaces)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle") {
                    Picker("Make", selection: $selectedMake) {
                        Text("Select make").tag("").foregroundStyle(.secondary)
                        ForEach(VehicleDatabase.makes, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: selectedMake) { _, _ in
                        selectedModel = ""
                        mpgText = ""
                    }

                    if !selectedMake.isEmpty {
                        Picker("Model", selection: $selectedModel) {
                            Text("Select model").tag("").foregroundStyle(.secondary)
                            ForEach(availableModels, id: \.self) { Text($0).tag($0) }
                        }
                        .onChange(of: selectedModel) { _, new in
                            guard !new.isEmpty,
                                  let lookup = VehicleDatabase.mpg(make: selectedMake, model: new)
                            else { return }
                            mpgText = "\(lookup)"
                        }
                    }

                    Picker("Year", selection: $selectedYear) {
                        ForEach(Self.yearRange, id: \.self) { Text(String($0)).tag($0) }
                    }
                }

                Section("Name") {
                    if !autoName.isEmpty && !useCustomName {
                        HStack {
                            Text(autoName)
                            Spacer()
                            Button("Rename") {
                                customName = autoName
                                useCustomName = true
                            }
                            .font(.caption)
                        }
                    } else {
                        TextField("e.g. My Honda Civic", text: $customName)
                    }
                }

                Section {
                    HStack {
                        Text("Fuel Economy")
                        Spacer()
                        TextField("–", text: $mpgText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 55)
                        Text("MPG")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    if isElectric {
                        Text("Electric vehicle — fuel cost will not be estimated.")
                    } else if mpgText.isEmpty {
                        Text("Auto-filled when you pick a make & model.")
                    }
                }

                Section {
                    TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $beaconUUID)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.system(.body, design: .monospaced))
                        .onChange(of: beaconUUID) { _, new in beaconUUID = new.uppercased() }
                } header: {
                    Text("Beacon UUID")
                } footer: {
                    Text("Find this in the beacon's manufacturer app (e.g. BeaconSET for MINEW). Looks like: E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")
                }
            }
            .navigationTitle("Add Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveVehicle() }.disabled(!canSave)
                }
            }
        }
    }

    private func saveVehicle() {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        let uuid = beaconUUID.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, UUID(uuidString: uuid) != nil else { return }

        let efficiency: Double
        if isElectric {
            efficiency = 0
        } else if mpg > 0 {
            efficiency = Units.mpgToLitersPer100Km(mpg)
        } else {
            efficiency = FuelEstimator.defaultLitersPer100Km
        }

        let vehicle = Vehicle(name: name, beaconUUID: uuid, fuelEfficiencyLitersPer100Km: efficiency)
        vehicle.year = selectedYear
        vehicle.make = selectedMake.isEmpty ? nil : selectedMake
        vehicle.vehicleModel = selectedModel.isEmpty ? nil : selectedModel
        modelContext.insert(vehicle)
        try? modelContext.save()
        sessionManager.beginMonitoring(vehicle: vehicle)
        if AuthService.shared.isAuthenticated {
            let captured = vehicle
            Task { await CloudKitService.shared.pushVehicle(captured) }
        }
        dismiss()
    }
}
