import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @StateObject private var authService = AuthService.shared
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // App branding
                VStack(spacing: 12) {
                    Image(systemName: "fuelpump.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)

                    Text("FairFuel")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Split fuel costs fairly with your household.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer()

                // Sign in section
                VStack(spacing: 16) {
                    if isLoading {
                        ProgressView("Signing in…")
                            .frame(height: 50)
                    } else {
                        SignInWithAppleButton(.signIn) { request in
                            let appleRequest = AuthService.shared.startSignIn()
                            request.requestedScopes = appleRequest.requestedScopes
                            request.nonce = appleRequest.nonce
                        } onCompletion: { result in
                            Task {
                                isLoading = true
                                errorMessage = nil
                                do {
                                    try await AuthService.shared.handleAuthorization(result)
                                } catch {
                                    errorMessage = error.localizedDescription
                                }
                                isLoading = false
                            }
                        }
                        .signInWithAppleButtonStyle(.black)
                        .frame(height: 50)
                        .cornerRadius(8)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.horizontal, 32)

                Text("Sign in is required to share trips and fuel costs with your household.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()
                    .frame(height: 32)
            }
        }
    }
}
