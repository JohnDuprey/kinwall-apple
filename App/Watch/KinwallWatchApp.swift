import SwiftUI
import WatchConnectivity
import KinwallKit
import WidgetKit

/// The Watch app (M4, docs/WIDGETS-AND-WATCH.md): Today, My chores and Lists. Its key comes from the
/// iPhone app over WatchConnectivity and is kept in the Watch's own Keychain.
@main
struct KinwallWatchApp: App {
    @State private var link = PhoneLink()

    var body: some Scene {
        WindowGroup {
            if let connection = link.connection {
                TabView {
                    TodayView(client: KinwallClient(connection))
                    ChoresView(client: KinwallClient(connection))
                    ListsView(client: KinwallClient(connection))
                }
                .tabViewStyle(.verticalPage)
                .id(connection.key) // a new household (or key) starts fresh
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "iphone").font(.title2).foregroundStyle(.secondary)
                    Text("Open Kinwall on your iPhone to connect this Watch.").font(.footnote).multilineTextAlignment(.center)
                }
                .padding()
            }
        }
    }
}

/// Receives the Watch's key from the iPhone app (App/iOS/WatchLink.swift).
@MainActor @Observable
final class PhoneLink: NSObject, WCSessionDelegate {
    private(set) var connection: Connection?
    private let store = SharedKeychain.widgetStore // shared with the complications

    override init() {
        super.init()
        connection = try? store.load()
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// What the iPhone sent, as plain values that can cross to the main actor.
    private struct Update: Sendable { let server: String?; let key: String?; let signedOut: Bool }
    private nonisolated static func update(_ context: [String: Any]) -> Update? {
        context.isEmpty ? nil : Update(server: context["server"] as? String, key: context["key"] as? String, signedOut: context["signedOut"] as? Bool == true)
    }

    private func apply(_ u: Update) {
        if u.signedOut {
            try? store.clear(); connection = nil
            WidgetCenter.shared.reloadAllTimelines()
        } else if let server = u.server.flatMap(URL.init(string:)), let key = u.key {
            let next = Connection(baseURL: server, key: key)
            try? store.save(next); connection = next
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard let u = Self.update(session.receivedApplicationContext) else { return }
        Task { @MainActor in apply(u) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let u = Self.update(context) else { return }
        Task { @MainActor in apply(u) }
    }
}
