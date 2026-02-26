import SwiftUI
import SwiftData

// Root view: shows onboarding on first launch, tabs once a profile exists.
struct RootView: View {
    @Query var profiles: [DriverProfile]

    var body: some View {
        if profiles.isEmpty {
            OnboardingView()
        } else {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Session", systemImage: "car.fill") }

            DriversView()
                .tabItem { Label("Profile", systemImage: "person.fill") }

            FuelView()
                .tabItem { Label("Fuel", systemImage: "fuelpump.fill") }
        }
    }
}
