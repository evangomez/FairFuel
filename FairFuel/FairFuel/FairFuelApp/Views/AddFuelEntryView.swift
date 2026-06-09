import SwiftUI
import SwiftData

struct AddFuelEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var gallonsText = ""
    @State private var costText = ""
    @State private var odometerText = ""

    private var isValid: Bool {
        guard let g = Double(gallonsText), let c = Double(costText) else { return false }
        return g > 0 && c > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Fill-up Details") {
                    HStack {
                        Text("Gallons")
                        Spacer()
                        TextField("0.000", text: $gallonsText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Total Cost")
                        Spacer()
                        Text("$").foregroundStyle(.secondary)
                        TextField("0.00", text: $costText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Odometer")
                        Spacer()
                        TextField("Optional", text: $odometerText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("mi").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Log Fill-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        guard let gallons = Double(gallonsText),
              let cost = Double(costText) else { return }
        // store internally as liters; odometer stored as km
        let liters = Units.gallonsToLiters(gallons)
        let odoMiles = Double(odometerText)
        let odoKm = odoMiles.map { $0 * 1.60934 }
        let entry = FuelEntry(liters: liters, totalCost: cost, odometer: odoKm)
        modelContext.insert(entry)
        try? modelContext.save()
        if let groupID = GroupManager.shared.groupID {
            let captured = entry
            Task { await CloudKitService.shared.pushFillUp(captured, groupID: groupID) }
        }
        dismiss()
    }
}
