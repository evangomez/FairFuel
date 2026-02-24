import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Session", systemImage: "car.fill")
                }

            DriversView()
                .tabItem {
                    Label("Drivers", systemImage: "person.2.fill")
                }

            FuelView()
                .tabItem {
                    Label("Fuel", systemImage: "fuelpump.fill")
                }
        }
    }
}
