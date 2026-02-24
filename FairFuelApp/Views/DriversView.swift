import SwiftUI
import SwiftData

// Lists registered drivers. Full implementation in Week 3.
struct DriversView: View {
    @Query var drivers: [Driver]

    var body: some View {
        NavigationStack {
            Group {
                if drivers.isEmpty {
                    ContentUnavailableView("No Drivers",
                                          systemImage: "person.badge.plus",
                                          description: Text("Add a driver to get started."))
                } else {
                    List(drivers) { driver in
                        VStack(alignment: .leading) {
                            Text(driver.name).font(.headline)
                            Text("\(driver.sessions.count) sessions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Drivers")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // Week 3: add driver flow
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}
