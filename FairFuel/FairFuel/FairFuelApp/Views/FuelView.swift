import SwiftUI
import SwiftData

// Fuel entry and cost allocation screen. Full implementation in Week 7.
struct FuelView: View {
    @Query(sort: \FuelEntry.date, order: .reverse) var entries: [FuelEntry]

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView("No Fuel Entries",
                                          systemImage: "fuelpump",
                                          description: Text("Log a refueling event to see cost splits."))
                } else {
                    List(entries) { entry in
                        VStack(alignment: .leading) {
                            Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.headline)
                            Text(String(format: "%.2f L  •  $%.2f", entry.liters, entry.totalCost))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Fuel")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // Week 7: add fuel entry flow
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}
