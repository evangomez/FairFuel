import SwiftUI
import SwiftData

struct EditVehicleView: View {
    let vehicle: Vehicle

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var selectedMake: String
    @State private var selectedModel: String
    @State private var selectedYear: Int
    @State private var mpgText: String
    @State private var beaconUUID: String

    private static let yearRange = Array((2000...Calendar.current.component(.year, from: Date())).reversed())

    init(vehicle: Vehicle) {
        self.vehicle = vehicle
        _name = State(initialValue: vehicle.name)
        _selectedMake = State(initialValue: vehicle.make ?? "")
        _selectedModel = State(initialValue: vehicle.vehicleModel ?? "")
        _selectedYear = State(initialValue: vehicle.year ?? Calendar.current.component(.year, from: Date()))
        _beaconUUID = State(initialValue: vehicle.beaconUUID)
        let mpg = vehicle.fuelEfficiencyLitersPer100Km > 0
            ? Int(Units.litersPer100KmToMPG(vehicle.fuelEfficiencyLitersPer100Km))
            : 0
        _mpgText = State(initialValue: mpg > 0 ? "\(mpg)" : "")
    }

    private var availableModels: [String] { VehicleDatabase.models(for: selectedMake) }
    private var mpg: Double { Double(mpgText) ?? 0 }
    private var isElectric: Bool { !mpgText.isEmpty && mpg == 0 }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
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
                    TextField("e.g. My Honda Civic", text: $name)
                }

                Section {
                    HStack {
                        Text("Fuel Economy")
                        Spacer()
                        TextField("–", text: $mpgText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 55)
                        Text("MPG").foregroundStyle(.secondary)
                    }
                } footer: {
                    if isElectric {
                        Text("Electric vehicle — fuel cost will not be estimated.")
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
                }
            }
            .navigationTitle("Edit Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedUUID = beaconUUID.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty, UUID(uuidString: trimmedUUID) != nil else { return }

        vehicle.name = trimmedName
        vehicle.beaconUUID = trimmedUUID
        vehicle.year = selectedYear
        vehicle.make = selectedMake.isEmpty ? nil : selectedMake
        vehicle.vehicleModel = selectedModel.isEmpty ? nil : selectedModel

        if isElectric {
            vehicle.fuelEfficiencyLitersPer100Km = 0
        } else if mpg > 0 {
            vehicle.fuelEfficiencyLitersPer100Km = Units.mpgToLitersPer100Km(mpg)
        }

        try? modelContext.save()
        if let groupID = GroupManager.shared.groupID {
            let captured = vehicle
            Task { await CloudKitService.shared.pushVehicle(captured, groupID: groupID) }
        }
        dismiss()
    }
}
