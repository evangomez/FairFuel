import SwiftUI
import SwiftData

// Lets the user register a new vehicle and program its NFC sticker.
struct AddVehicleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var vehicleName = ""
    @State private var efficiencyText = "9.4"
    @State private var writeState: WriteState = .idle

    enum WriteState {
        case idle, writing, success, failure(String)
    }

    private var efficiency: Double { Double(efficiencyText) ?? 9.4 }
    private var canSave: Bool { !vehicleName.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Vehicle Details") {
                    TextField("Vehicle name (e.g. Honda Civic)", text: $vehicleName)
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
                    switch writeState {
                    case .idle:
                        Button(action: addVehicle) {
                            Label("Save & Program NFC Tag", systemImage: "wave.3.right")
                        }
                        .disabled(!canSave)

                    case .writing:
                        HStack {
                            ProgressView()
                            Text("Hold phone to NFC sticker…")
                                .foregroundStyle(.secondary)
                        }

                    case .success:
                        Label("Tag programmed! Vehicle ready.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)

                    case .failure(let msg):
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Tag write failed", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button("Try Again") { writeState = .idle }
                        }
                    }
                } footer: {
                    Text("Have the NFC sticker ready. The app will write the vehicle ID to it automatically.")
                }
            }
            .navigationTitle("Add Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if case .success = writeState {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }

    private func addVehicle() {
        let name = vehicleName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let vehicle = Vehicle(name: name, fuelEfficiencyLitersPer100Km: efficiency)
        modelContext.insert(vehicle)
        try? modelContext.save()

        writeState = .writing
        sessionManager.writeVehicleTag(vehicleID: vehicle.id.uuidString) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    writeState = .success
                case .failure(let error):
                    writeState = .failure(error.localizedDescription)
                }
            }
        }
    }
}
