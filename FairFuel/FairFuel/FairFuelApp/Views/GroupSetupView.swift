import SwiftUI

struct GroupSetupView: View {
    enum Mode { case create, join }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss

    @State private var generatedCode: String? = nil
    @State private var joinInput: String = ""
    @State private var joinError: String? = nil
    @State private var joinedSuccessfully = false

    var body: some View {
        NavigationStack {
            Form {
                if mode == .create {
                    createSection
                } else {
                    joinSection
                }
            }
            .navigationTitle(mode == .create ? "Create Group" : "Join Group")
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
                Text("Generate a code and share it with your household. Anyone who enters it will see your trips in cost splits.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            if let code = generatedCode {
                Section("Your Group Code") {
                    HStack {
                        Text(code)
                            .font(.system(.title2, design: .monospaced))
                            .fontWeight(.semibold)
                        Spacer()
                        ShareLink(item: "Join my FairFuel group! Code: \(code)") {
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
                    Button("Done") { dismiss() }
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } else {
                Section {
                    Button("Generate Code") {
                        GroupManager.shared.createGroup()
                        generatedCode = GroupManager.shared.displayCode
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
                Text("Enter the 8-character code shared by another household member.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section("Group Code") {
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
                        Text("Go back to Profile & Vehicles to adopt shared vehicles from your group.")
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
                    Button("Join Group") {
                        if GroupManager.shared.join(code: joinInput) {
                            joinedSuccessfully = true
                        } else {
                            joinError = "Invalid code. Use the format XXXX-XXXX."
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(joinInput.replacingOccurrences(of: "-", with: "").count < 8)
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
