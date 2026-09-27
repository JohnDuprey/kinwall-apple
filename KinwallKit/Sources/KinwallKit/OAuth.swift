import Foundation
import CryptoKit
#if canImport(Security)
import Security
#endif

/// Signing in with Kinwall's OAuth (the same authorization server MCP clients use): the app
/// registers itself, opens the consent screen in a Safari sheet (where passkeys work on any
/// domain), and swaps the returned code for tokens. Access tokens last an hour; refresh tokens
/// 90 days and rotate on every use. The app's link scheme is reverse-domain (RFC 8252).
public enum OAuth {
    public static let redirectScheme = "family.kinwall.app"
    public static let redirectURI = "\(redirectScheme):/oauth"

    public struct Tokens: Codable, Equatable, Sendable {
        public var baseURL: URL
        public var clientId: String
        public var accessToken: String
        public var refreshToken: String
        public var expiresAt: Date
        public var scope: String
        /// Refresh a little early so a request never goes out with a token about to lapse.
        public func needsRefresh(now: Date = .now) -> Bool { expiresAt.timeIntervalSince(now) < 5 * 60 }
    }

    /// PKCE (RFC 7636, S256): a random verifier and its SHA-256 challenge.
    public struct PKCE: Sendable {
        public let verifier: String
        public let challenge: String
        public init(verifier: String = OAuth.randomURLSafe(32)) {
            self.verifier = verifier
            challenge = OAuth.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        }
    }

    public static func randomURLSafe(_ bytes: Int) -> String {
        base64URL(Data((0..<bytes).map { _ in UInt8.random(in: .min ... .max) }))
    }
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

public struct OAuthError: Error, Equatable, LocalizedError, Sendable {
    public let code: String
    public let message: String
    public var errorDescription: String? { message }
    /// The refresh token is gone (revoked, expired or already used): sign in again.
    public var needsSignIn: Bool { code == "invalid_grant" }
}

/// The HTTP side of the flow. The Safari sheet itself (ASWebAuthenticationSession) lives in the app.
public struct OAuthClient: Sendable {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Dynamic client registration (RFC 7591). Cache the id per server; registering again is harmless.
    public func register(name: String) async throws -> String {
        struct Body: Encodable { let client_name: String; let redirect_uris: [String] }
        struct Reply: Decodable { let client_id: String }
        var req = URLRequest(url: baseURL.appending(path: "oauth/register"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(Body(client_name: name, redirect_uris: [OAuth.redirectURI]))
        return try await send(req, as: Reply.self).client_id
    }

    /// Where the Safari sheet goes. `scope` "kinwall:admin" lets the approver pick admin or display.
    public func authorizeURL(clientId: String, pkce: OAuth.PKCE, state: String, scope: String = "kinwall:admin") -> URL {
        var url = baseURL.appending(path: "oauth/authorize")
        url.append(queryItems: [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: OAuth.redirectURI),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
        ])
        return url
    }

    /// Reads the code from the link the sheet came back with, checking `state` and the error field.
    public static func code(from callback: URL, state: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw OAuthError(code: error, message: error == "access_denied" ? "Sign-in was declined." : (value("error_description") ?? error))
        }
        guard value("state") == state, let code = value("code") else {
            throw OAuthError(code: "invalid_response", message: "The sign-in didn't come back as expected. Try again.")
        }
        return code
    }

    public func exchange(code: String, pkce: OAuth.PKCE, clientId: String) async throws -> OAuth.Tokens {
        try await tokenRequest(["grant_type": "authorization_code", "code": code, "code_verifier": pkce.verifier, "client_id": clientId, "redirect_uri": OAuth.redirectURI], clientId: clientId)
    }

    public func refresh(_ tokens: OAuth.Tokens) async throws -> OAuth.Tokens {
        try await tokenRequest(["grant_type": "refresh_token", "refresh_token": tokens.refreshToken, "client_id": tokens.clientId], clientId: tokens.clientId)
    }

    /// Ends the grant on the server (its access and refresh tokens stop working). Best effort.
    public func revoke(_ tokens: OAuth.Tokens) async {
        var req = URLRequest(url: baseURL.appending(path: "oauth/revoke"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.form(["token": tokens.refreshToken, "client_id": tokens.clientId])
        _ = try? await session.data(for: req)
    }

    // MARK: Plumbing

    private struct TokenReply: Decodable { let access_token: String; let refresh_token: String; let expires_in: Double; let scope: String }
    private struct ErrorReply: Decodable { let error: String; let error_description: String? }

    private func tokenRequest(_ fields: [String: String], clientId: String) async throws -> OAuth.Tokens {
        var req = URLRequest(url: baseURL.appending(path: "oauth/token"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.form(fields)
        let r = try await send(req, as: TokenReply.self)
        return OAuth.Tokens(baseURL: baseURL, clientId: clientId, accessToken: r.access_token, refreshToken: r.refresh_token,
                            expiresAt: Date(timeIntervalSinceNow: r.expires_in), scope: r.scope)
    }

    private func send<T: Decodable>(_ req: URLRequest, as: T.Type) async throws -> T {
        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let e = try? JSONDecoder().decode(ErrorReply.self, from: data)
            throw OAuthError(code: e?.error ?? "http_\(status)", message: e?.error_description ?? e?.error ?? HTTPURLResponse.localizedString(forStatusCode: status))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(fields.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
    }
}

#if canImport(Security)
/// The OAuth tokens as one Keychain item, beside the connection (ConnectionStore).
public struct KeychainTokenStore: Sendable {
    public let service: String
    public init(service: String = "family.kinwall.oauth") { self.service = service }
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "household"] }

    public func load() -> OAuth.Tokens? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(OAuth.Tokens.self, from: data)
    }

    public func save(_ tokens: OAuth.Tokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let attrs: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(attrs) { $1 } as CFDictionary, nil)
        }
    }

    public func clear() { SecItemDelete(query as CFDictionary) }
}
#endif
