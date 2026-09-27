import Foundation
import WatchConnectivity
import KinwallKit

/// Gives the Kinwall Watch app its own everyday-access key (docs/WIDGETS-AND-WATCH.md): minted with
/// the widgets' key, kept here so it's minted once, and sent to the Watch as application context
/// (delivered whenever the Watch is next reachable). Revoked on sign-out.
final class WatchLink: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchLink()
    private let store = KeychainConnectionStore(service: "family.kinwall.watch")

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sync() async {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let widgets = try? SharedKeychain.widgetStore.load() else { return }
        var watch = try? store.load()
        if watch?.baseURL != widgets.baseURL {
            guard let minted = try? await KinwallClient(widgets).createDeviceKey(name: "Apple Watch") else { return }
            watch = Connection(baseURL: widgets.baseURL, key: minted.key)
            try? store.save(watch!)
        }
        guard let watch else { return }
        try? session.updateApplicationContext(["server": watch.baseURL.absoluteString, "key": watch.key])
    }

    func signOut() async {
        if let watch = try? store.load() { try? await KinwallClient(watch).revokeOwnKey() }
        try? store.clear()
        if WCSession.isSupported(), WCSession.default.activationState == .activated {
            try? WCSession.default.updateApplicationContext(["signedOut": true])
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) { Task { await sync() } }
    func sessionWatchStateDidChange(_ session: WCSession) { Task { await sync() } } // e.g. the Watch app was just installed
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() } // switched to another Watch
}
