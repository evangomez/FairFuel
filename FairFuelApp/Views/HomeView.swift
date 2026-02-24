import SwiftUI

// Primary screen: shows active session status and NFC scan button.
// Full implementation in Week 7.
struct HomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Image(systemName: "car.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                Text("No Active Session")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Button {
                    // Week 3: trigger NFCService.startScanning()
                } label: {
                    Label("Scan NFC Tag to Start", systemImage: "wave.3.right")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)
            }
            .navigationTitle("FairFuel")
        }
    }
}
