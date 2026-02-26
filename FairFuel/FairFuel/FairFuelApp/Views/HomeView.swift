import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var sessionManager: SessionManager
    @Query var profiles: [DriverProfile]

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()
                stateView
                Spacer()
            }
            .padding()
            .navigationTitle("FairFuel")
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch sessionManager.state {
        case .idle:
            idleView

        case .pending(let vehicle):
            pendingView(vehicle: vehicle)

        case .active(let session):
            ActiveSessionView(session: session)

        case .stopping(let session):
            VStack(spacing: 16) {
                ActiveSessionView(session: session)
                Text("Ending session in 10 seconds…")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Keep Session Active", role: .cancel) {
                    sessionManager.endSessionManually()
                }
            }

        case .ended:
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                Text("Trip saved.")
                    .font(.title3)
            }
        }
    }

    private var idleView: some View {
        VStack(spacing: 24) {
            Image(systemName: "car.circle.fill")
                .font(.system(size: 90))
                .foregroundStyle(.blue)

            VStack(spacing: 6) {
                Text("Ready to Drive")
                    .font(.title2).bold()
                if let name = profiles.first?.name {
                    Text("Logged in as \(name)")
                        .foregroundStyle(.secondary)
                }
                Text("Get close to your car and the app will detect it automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    private func pendingView(vehicle: Vehicle) -> some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.4)

            VStack(spacing: 6) {
                Text(vehicle.name)
                    .font(.title2).bold()
                Text("Detected nearby — confirming you're driving…")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Cancel", role: .cancel) {
                sessionManager.endSessionManually()
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Active Session Card

private struct ActiveSessionView: View {
    let session: DrivingSession
    @EnvironmentObject private var sessionManager: SessionManager

    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "car.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Session Active")
                .font(.title2).bold()

            HStack(spacing: 40) {
                stat(label: "Distance", value: String(format: "%.1f km", session.distanceKm))
                stat(label: "Time", value: elapsed(from: session.startTime, to: now))
            }

            if let name = session.vehicle?.name {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("End Session", role: .destructive) {
                sessionManager.endSessionManually()
            }
            .buttonStyle(.bordered)
        }
        .onReceive(timer) { now = $0 }
    }

    private func stat(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3).bold()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func elapsed(from start: Date, to end: Date) -> String {
        let s = Int(end.timeIntervalSince(start))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }
}
