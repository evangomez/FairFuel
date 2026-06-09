import Foundation
import CryptoKit
import AuthenticationServices

// MARK: - Session Model

struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userId: String
    let displayName: String

    private enum CodingKeys: String, CodingKey {
        case accessToken, refreshToken, expiresAt, userId, displayName
    }
}

// MARK: - AuthService

@MainActor
final class AuthService: NSObject, ObservableObject {
    static let shared = AuthService()

    @Published private(set) var session: AuthSession?

    var isAuthenticated: Bool { session != nil }
    var accessToken: String? { session?.accessToken }
    var userId: String? { session?.userId }

    private let keychainKey = "fairfuel.auth.session"
    private let base = SupabaseConfig.projectURL
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // Raw nonce stored for Supabase verification; SHA-256 hash is sent to Apple.
    private var currentRawNonce: String?

    private override init() {
        super.init()
        loadSessionFromKeychain()
    }

    // MARK: - Sign In With Apple

    /// Call this to create the Apple ID request. Store the returned request's nonce.
    func startSignIn() -> ASAuthorizationAppleIDRequest {
        let rawNonce = generateNonce()
        currentRawNonce = rawNonce
        let hashedNonce = sha256(rawNonce)
        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce
        return request
    }

    /// Call this from the ASAuthorizationController completion handler.
    func handleAuthorization(_ result: Result<ASAuthorization, Error>) async throws {
        switch result {
        case .failure(let error):
            print("[Auth] Apple authorization failed: \(error)")
            throw error
        case .success(let auth):
            guard let appleCredential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = appleCredential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8),
                  let rawNonce = currentRawNonce else {
                print("[Auth] Missing identity token or nonce")
                throw AuthError.missingCredentials
            }

            // Extract display name from Apple credential (only provided on first sign-in)
            var displayName = ""
            if let fullName = appleCredential.fullName {
                let given = fullName.givenName ?? ""
                let family = fullName.familyName ?? ""
                displayName = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
            }

            try await exchangeAppleToken(identityToken: identityToken, rawNonce: rawNonce, displayName: displayName)
        }
    }

    // MARK: - Token Refresh

    /// Refreshes the session if it will expire within 5 minutes.
    func refreshIfNeeded() async {
        guard let current = session else { return }
        let fiveMinutesFromNow = Date().addingTimeInterval(5 * 60)
        guard current.expiresAt < fiveMinutesFromNow else { return }

        print("[Auth] Token expiring soon — refreshing")
        await refreshToken(current.refreshToken, displayName: current.displayName)
    }

    // MARK: - Sign Out

    func signOut() {
        session = nil
        KeychainService.delete(for: keychainKey)
        print("[Auth] Signed out — session cleared from Keychain")
    }

    // MARK: - Private: Network

    private func exchangeAppleToken(identityToken: String, rawNonce: String, displayName: String) async throws {
        let url = URL(string: "\(base)/auth/v1/token?grant_type=id_token")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")

        let body: [String: Any] = [
            "provider": "apple",
            "id_token": identityToken,
            "nonce": rawNonce
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
            let msg = String(data: data, encoding: .utf8) ?? ""
            print("[Auth] GoTrue token exchange failed: HTTP \(http.statusCode) — \(msg)")
            throw AuthError.serverError(http.statusCode, msg)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AuthError.invalidResponse
        }

        let resolvedDisplayName = displayName.isEmpty ? (session?.displayName ?? "Driver") : displayName
        let newSession = parseSession(from: json, displayName: resolvedDisplayName)
        guard let newSession = newSession else {
            throw AuthError.invalidResponse
        }

        session = newSession
        saveSessionToKeychain(newSession)
        print("[Auth] Sign in successful — userId: \(newSession.userId)")

        // Upsert profile row
        await upsertProfile(userId: newSession.userId, displayName: newSession.displayName, token: newSession.accessToken)
    }

    private func refreshToken(_ refreshToken: String, displayName: String) async {
        let url = URL(string: "\(base)/auth/v1/token?grant_type=refresh_token")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")

        let body: [String: Any] = ["refresh_token": refreshToken]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                let msg = String(data: data, encoding: .utf8) ?? ""
                print("[Auth] Token refresh failed: HTTP \(http.statusCode) — \(msg)")
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newSession = parseSession(from: json, displayName: displayName) else {
                print("[Auth] Token refresh — invalid response")
                return
            }
            session = newSession
            saveSessionToKeychain(newSession)
            print("[Auth] Token refreshed — expires \(newSession.expiresAt)")
        } catch {
            print("[Auth] Token refresh error: \(error)")
        }
    }

    private func upsertProfile(userId: String, displayName: String, token: String) async {
        let url = URL(string: "\(base)/rest/v1/profiles")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("resolution=merge-duplicates", forHTTPHeaderField: "Prefer")

        let body: [String: Any] = [
            "id": userId,
            "display_name": displayName
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                let msg = String(data: data, encoding: .utf8) ?? ""
                print("[Auth] Profile upsert failed: HTTP \(http.statusCode) — \(msg)")
            } else {
                print("[Auth] Profile upserted for userId: \(userId)")
            }
        } catch {
            print("[Auth] Profile upsert error: \(error)")
        }
    }

    // MARK: - Private: Keychain

    private func saveSessionToKeychain(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        KeychainService.save(data, for: keychainKey)
    }

    private func loadSessionFromKeychain() {
        guard let data = KeychainService.load(for: keychainKey),
              let decoded = try? JSONDecoder().decode(AuthSession.self, from: data) else {
            return
        }
        session = decoded
        print("[Auth] Loaded session from Keychain — userId: \(decoded.userId), expires: \(decoded.expiresAt)")
    }

    // MARK: - Private: Parsing

    private func parseSession(from json: [String: Any], displayName: String) -> AuthSession? {
        guard
            let accessToken = json["access_token"] as? String,
            let refreshToken = json["refresh_token"] as? String
        else { return nil }

        // expiresAt: prefer expires_at (ISO8601 string), fall back to expires_in (seconds offset)
        let expiresAt: Date
        if let expiresAtStr = json["expires_at"] as? String, let parsed = iso.date(from: expiresAtStr) {
            expiresAt = parsed
        } else if let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue {
            expiresAt = Date().addingTimeInterval(expiresIn)
        } else {
            expiresAt = Date().addingTimeInterval(3600)
        }

        // userId: from user.id nested object
        let userId: String
        if let user = json["user"] as? [String: Any], let uid = user["id"] as? String {
            userId = uid
        } else if let uid = json["user_id"] as? String {
            userId = uid
        } else {
            return nil
        }

        return AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userId: userId,
            displayName: displayName
        )
    }

    // MARK: - Private: Crypto

    private func generateNonce(length: Int = 32) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var result = ""
        var randomBytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &randomBytes)
        for byte in randomBytes {
            result.append(chars[Int(byte) % chars.count])
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hash = SHA256.hash(data: inputData)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - AuthError

enum AuthError: LocalizedError {
    case missingCredentials
    case serverError(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "Missing Apple ID credentials."
        case .serverError(let code, let msg): return "Server error \(code): \(msg)"
        case .invalidResponse: return "Unexpected server response."
        }
    }
}
