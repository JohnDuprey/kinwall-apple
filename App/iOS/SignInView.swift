import SwiftUI
import AuthenticationServices
import KinwallKit

/// Sign in with Kinwall's OAuth in a Safari sheet (passkeys work there on any domain), or pair
/// with a code an admin approves (kids' phones, wall iPads).
struct SignInView: View {
    let server: URL
    let session: Session
    let onChangeServer: () -> Void
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var busy = false
    @State private var problem: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Sign in to Kinwall").font(.largeTitle.bold())
                Text(server.host() ?? server.absoluteString).font(.headline).foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                Button(action: signIn) {
                    Group { if busy { ProgressView() } else { Text("Sign in") } }.frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(busy)
                Text("Opens your Kinwall in a secure sheet. Sign in with your passkey and approve this app.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let problem { Text(problem).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
            }
            Divider()
            VStack(spacing: 8) {
                Button("Pair with a code instead") { session.choosePairing() }
                    .buttonStyle(.bordered).controlSize(.large).disabled(busy)
                Text("For a child's phone or a wall iPad: this device shows a code, and an admin approves it in Kinwall under Settings → Access.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Use a different server", action: onChangeServer).font(.footnote)
        }
        .padding(24)
        .frame(maxWidth: 520)
    }

    private func signIn() {
        busy = true; problem = nil
        Task {
            defer { busy = false }
            do {
                let client = OAuthClient(baseURL: server)
                let clientId = try await client.register(name: "Kinwall for \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")")
                let pkce = OAuth.PKCE(), state = OAuth.randomURLSafe(12)
                let callback = try await webAuth.authenticate(
                    using: client.authorizeURL(clientId: clientId, pkce: pkce, state: state),
                    callbackURLScheme: OAuth.redirectScheme,
                    preferredBrowserSession: .shared) // Safari's own context, so saved passkeys and sign-ins are there
                let code = try OAuthClient.code(from: callback, state: state)
                session.signedIn(try await client.exchange(code: code, pkce: pkce, clientId: clientId))
            } catch let e as ASWebAuthenticationSessionError where e.code == .canceledLogin {
                // Closed the sheet: stay here quietly.
            } catch {
                problem = error.localizedDescription
            }
        }
    }
}
