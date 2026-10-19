import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

struct SpotifyTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

enum SpotifyAuthError: LocalizedError {
    case notConfigured
    case notLoggedIn
    case cancelled
    case tokenRequestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Falta el Client ID de Spotify en Config.xcconfig"
        case .notLoggedIn: return "Conecta tu cuenta de Spotify"
        case .cancelled: return "Inicio de sesión cancelado"
        case .tokenRequestFailed(let code, let body): return "Spotify rechazó el token (\(code)): \(body)"
        }
    }
}

/// OAuth 2.0 Authorization Code + PKCE. No client secret ships in the app.
@MainActor
final class SpotifyAuth: NSObject, ObservableObject {
    @Published private(set) var isLoggedIn = false

    private static let keychainAccount = "spotify.tokens"
    private var tokens: SpotifyTokens? {
        didSet {
            isLoggedIn = tokens != nil
            if let tokens { Keychain.save(tokens, account: Self.keychainAccount) }
            else { Keychain.delete(account: Self.keychainAccount) }
        }
    }
    private var refreshTask: Task<String, Error>?
    private var webSession: ASWebAuthenticationSession?

    override init() {
        super.init()
        // Property observers don't fire inside init, so sync the flag explicitly.
        tokens = Keychain.load(SpotifyTokens.self, account: Self.keychainAccount)
        isLoggedIn = tokens != nil
    }

    func logOut() { tokens = nil }

    func logIn() async throws {
        guard AppConfig.isSpotifyConfigured else { throw SpotifyAuthError.notConfigured }

        let verifier = Self.randomVerifier()
        let challenge = Self.challenge(for: verifier)
        let state = UUID().uuidString

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: AppConfig.spotifyClientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: AppConfig.spotifyRedirectURI),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "state", value: state),
            .init(name: "scope", value: AppConfig.spotifyScopes.joined(separator: " "))
        ]

        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: AppConfig.spotifyRedirectScheme
            ) { url, error in
                if let url { continuation.resume(returning: url) }
                else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: SpotifyAuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? SpotifyAuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.webSession = session
            session.start()
        }
        webSession = nil

        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == state,
              let code = items.first(where: { $0.name == "code" })?.value else {
            let reason = items.first(where: { $0.name == "error" })?.value ?? "respuesta inválida"
            throw SpotifyAuthError.tokenRequestFailed(0, reason)
        }

        tokens = try await requestTokens([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": AppConfig.spotifyRedirectURI,
            "client_id": AppConfig.spotifyClientID,
            "code_verifier": verifier
        ], previousRefreshToken: nil)
    }

    /// Returns a non-expired access token, refreshing at most once concurrently.
    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = tokens else { throw SpotifyAuthError.notLoggedIn }
        if !forceRefresh, current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
        if let refreshTask { return try await refreshTask.value }

        let task = Task<String, Error> { [weak self] in
            guard let self else { throw SpotifyAuthError.notLoggedIn }
            let refreshed = try await self.requestTokens([
                "grant_type": "refresh_token",
                "refresh_token": current.refreshToken,
                "client_id": AppConfig.spotifyClientID
            ], previousRefreshToken: current.refreshToken)
            self.tokens = refreshed
            return refreshed.accessToken
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            return try await task.value
        } catch SpotifyAuthError.tokenRequestFailed(let status, let body) where status == 400 {
            tokens = nil // refresh token revoked → force a new login
            throw SpotifyAuthError.tokenRequestFailed(status, body)
        }
    }

    private func requestTokens(_ form: [String: String], previousRefreshToken: String?) async throws -> SpotifyTokens {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = form
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw SpotifyAuthError.tokenRequestFailed(status, String(data: data, encoding: .utf8) ?? "")
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let expires_in: Double
            let refresh_token: String?
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refresh = decoded.refresh_token ?? previousRefreshToken else {
            throw SpotifyAuthError.tokenRequestFailed(status, "sin refresh_token")
        }
        return SpotifyTokens(accessToken: decoded.access_token, refreshToken: refresh,
                             expiresAt: Date().addingTimeInterval(decoded.expires_in))
    }

    // MARK: - PKCE helpers

    private static func randomVerifier() -> String {
        let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var generator = SystemRandomNumberGenerator()
        return String((0..<64).map { _ in charset.randomElement(using: &generator)! })
    }

    private static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension SpotifyAuth: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
            return scene?.keyWindow ?? scene?.windows.first ?? ASPresentationAnchor()
        }
    }
}
