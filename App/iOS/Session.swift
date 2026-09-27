import Foundation
import Observation
import KinwallKit

/// How this device is signed in to the household: OAuth tokens (kept fresh here), or a paired
/// key the web app holds itself. Nil means "show the sign-in screen".
@MainActor @Observable
final class Session {
    enum Mode: Equatable { case oauth, paired }

    private(set) var mode: Mode?
    private(set) var accessToken: String?
    private let tokenStore = KeychainTokenStore()
    private let pairedKey = "signedInWithPairing"
    private var tokens: OAuth.Tokens?
    private var refreshing: Task<String?, Never>?

    init(server: URL?) {
        if let server, let saved = tokenStore.load(), saved.baseURL == server {
            tokens = saved; accessToken = saved.accessToken; mode = .oauth
        } else if server != nil, UserDefaults.standard.bool(forKey: pairedKey) {
            mode = .paired
        }
    }

    func signedIn(_ tokens: OAuth.Tokens) {
        tokenStore.save(tokens)
        self.tokens = tokens; accessToken = tokens.accessToken; mode = .oauth
        UserDefaults.standard.removeObject(forKey: pairedKey)
    }

    func choosePairing() {
        UserDefaults.standard.set(true, forKey: pairedKey)
        mode = .paired
    }

    /// A token that's good for at least five minutes, refreshing if needed. Nil when the grant is
    /// gone (revoked, or the refresh token expired): the caller signs out.
    func freshToken() async -> String? {
        guard let tokens else { return nil }
        if !tokens.needsRefresh() { return tokens.accessToken }
        if let refreshing { return await refreshing.value } // one refresh at a time: refresh tokens rotate
        let task = Task { () -> String? in
            do {
                let next = try await OAuthClient(baseURL: tokens.baseURL).refresh(tokens)
                self.tokenStore.save(next)
                self.tokens = next; self.accessToken = next.accessToken
                return next.accessToken
            } catch let e as OAuthError where e.needsSignIn {
                return nil
            } catch {
                return tokens.accessToken // offline: keep the old one and try again later
            }
        }
        refreshing = task
        defer { refreshing = nil }
        return await task.value
    }

    /// Back to the sign-in screen, ending the OAuth grant on the server.
    func signOut() async {
        if let tokens { await OAuthClient(baseURL: tokens.baseURL).revoke(tokens) }
        tokenStore.clear()
        await WidgetKey.revoke()
        await Reminders.clear()
        await WatchLink.shared.signOut()
        UserDefaults.standard.removeObject(forKey: pairedKey)
        tokens = nil; accessToken = nil; mode = nil
    }
}
