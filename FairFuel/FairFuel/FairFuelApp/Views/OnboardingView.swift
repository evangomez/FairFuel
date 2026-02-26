import SwiftUI
import SwiftData

// Shown on first launch. Creates the local DriverProfile for this device.
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)

                VStack(spacing: 8) {
                    Text("Welcome to FairFuel")
                        .font(.title)
                        .bold()
                    Text("Enter your name so your trips are tracked under your profile.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                TextField("Your name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 32)
                    .focused($nameFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { saveProfile() }

                Button(action: saveProfile) {
                    Text("Get Started")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(name.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.horizontal, 32)

                Spacer()
            }
            .navigationTitle("")
            .onAppear { nameFieldFocused = true }
        }
    }

    private func saveProfile() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let profile = DriverProfile(name: trimmed)
        modelContext.insert(profile)
        try? modelContext.save()
    }
}
