import SwiftUI

struct GroupSetupView: View {
    enum Mode {
        case create(vehicleID: String, vehicleName: String)
        case join
    }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss

    // Create mode state
    @State private var generatedCode: String? = nil
    @State private var isGenerating = false

    // Join mode state
    @State private var joinInput: String = ""
    @State private var joinError: String? = nil
    @State private var joinedSuccessfully = false
    @State private var joinedVehicleName: String? = nil
    @State private var isJoining = false

    private var isCreateMode: Bool {
        if case .create = mode { return true }
        return false
    }

    private var createVehicleID: String {
        if case .create(let vehicleID, _) = mode { return vehicleID }
        return ""
    }

    private var createVehicleName: String {
        if case .create(_, let vehicleName) = mode { return vehicleName }
        return ""
    }

    var body: some View {
        NavigationStack {
            Form {
                if isCreateMode {
                    createSection
                } else {
                    joinSection
                }
            }
            .navigationTitle(isCreateMode ? "Invite to \(createVehicleName)" : "Join a Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Create

    private var createSection: some View {
        Group {
            Section {
                Text("Generate a time-limited invite code and share it with a household member. They can use it to join \(createVehicleName) and see shared trips.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            if let code = generatedCode {
                Section("Invite Code") {
                    HStack {
                        Text(code)
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.semibold)
                        Spacer()
                        ShareLink(item: "Join my FairFuel vehicle! Enter code: \(code)") {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Button {
                            UIPasteboard.general.string = code
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("This code expires in 7 days.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Section {
                    Button("Done") { dismiss() }
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else if isGenerating {
                Section {
                    HStack {
                        ProgressView()
                        Text("Generating…")
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                Section {
                    Button("Generate Invite Code") {
                        Task {
                            isGenerating = true
                            generatedCode = await GroupManager.shared.createInvite(vehicleID: createVehicleID)
                            isGenerating = false
                            if generatedCode == nil {
                                // Surface error in a simple way — code generation failed
                                print("[GroupSetupView] Failed to generate invite code")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    // MARK: - Join

    private var joinSection: some View {
        Group {
            Section {
                Text("Enter the 8-character code shared by another household member to join their vehicle.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section("Invite Code") {
                TextField("XXXX-XXXX", text: $joinInput)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .onChange(of: joinInput) { _, new in
                        joinError = nil
                        joinInput = formatCodeInput(new)
                    }
                if let error = joinError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            if joinedSuccessfully {
                Section {
                    VStack(spacing: 8) {
                        Label("Joined successfully!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        if let vehicleName = joinedVehicleName {
                            Text("You are now a member of \(vehicleName).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        Text("Go back to Profile & Vehicles to adopt shared vehicles.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                Section {
                    Button("Done") { dismiss() }
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                Section {
                    if isJoining {
                        HStack {
                            ProgressView()
                            Text("Joining…")
                                .foregroundStyle(.secondary)
                                .padding(.leading, 8)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Button("Join Vehicle") {
                            Task {
                                let clean = joinInput.replacingOccurrences(of: "-", with: "")
                                guard clean.count == 8 else {
                                    joinError = "Invalid code. Use the format XXXX-XXXX."
                                    return
                                }
                                isJoining = true
                                joinError = nil
                                if let vehicleName = await GroupManager.shared.redeemInvite(code: joinInput) {
                                    joinedVehicleName = vehicleName
                                    joinedSuccessfully = true
                                } else {
                                    joinError = "Code not found, already used, or expired. Ask your household for a new one."
                                }
                                isJoining = false
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .disabled(joinInput.replacingOccurrences(of: "-", with: "").count < 8)
                    }
                }
            }
        }
    }

    /// Formats input as XXXX-XXXX while typing.
    private func formatCodeInput(_ raw: String) -> String {
        let clean = raw.uppercased().replacingOccurrences(of: "-", with: "")
        let capped = String(clean.prefix(8))
        if capped.count > 4 {
            return "\(capped.prefix(4))-\(capped.dropFirst(4))"
        }
        return capped
    }
}
