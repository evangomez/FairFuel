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
            .alert("NFC Error", isPresented: Binding(
                get: { sessionManager.nfcError != nil },
                set: { if !$0 { sessionManager.nfcError = nil } }
            )) {
                Button("OK") { sessionManager.nfcError = nil }
            } message: {
                Text(sessionManager.nfcError ?? "")
            }
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch sessionManager.state {
        case .idle:
            idleView

        case .starting:
            VStack(spacing: 16) {
                ProgressView()
                Text("Starting session…")
                    .foregroundStyle(.secondary)
            }

        case .active(let session):
            ActiveSessionView(session: session)

        case .stopping(let session):
            VStack(spacing: 16) {
                ActiveSessionView(session: session)
                Text("Ending in 10 seconds…")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Keep Session", role: .cancel) {
                    sessionManager.endSessionManually()
                }
            }

        case .ended:
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                Text("Session saved.")
                    .font(.title3)
            }
        }
    }

    private var idleView: some View {
        VStack(spacing: 24) {
            Image(systemName: "car.circle.fill")
                .font(.system(size: 90))
                .foregroundStyle(.blue)

            VStack(spacing: 4) {
                Text("No Active Session")
                    .font(.title2)
                    .bold()
                if let name = profiles.first?.name {
                    Text("Driving as \(name)")
                        .foregroundStyle(.secondary)
                }
            }

            Button(action: { sessionManager.scanToStartSession() }) {
                Label("Tap Vehicle Tag to Start", systemImage: "wave.3.right")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

// MARK: - Active Session Card

private struct ActiveSessionView: View {
    let session: DrivingSession
    @EnvironmentObject private var sessionManager: SessionManager

    // Ticker to refresh elapsed time every second
    @State private var now = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "car.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)

            Text("Session Active")
                .font(.title2).bold()

            HStack(spacing: 32) {
                stat(label: "Distance", value: String(format: "%.1f km", session.distanceKm))
                stat(label: "Duration", value: formatDuration(session.startTime, to: now))
            }

            if let vehicleName = session.vehicle?.name {
                Text(vehicleName)
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

    private func formatDuration(_ start: Date, to end: Date) -> String {
        let secs = Int(end.timeIntervalSince(start))
        let h = secs / 3600, m = (secs % 3600) / 60, s = secs % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
