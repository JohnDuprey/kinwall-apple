import Foundation
import WidgetKit
import UIKit
import KinwallKit

/// The widgets' own key (docs/WIDGETS-AND-WATCH.md): minted once per server with whatever key the
/// app is signed in with, revoked on sign-out.
enum WidgetKey {
    static func ensure(server: URL, using key: String) async {
        let store = SharedKeychain.widgetStore
        if let saved = try? store.load(), saved.baseURL == server { return }
        let name = "Widgets on \(await deviceName())"
        guard let minted = try? await KinwallClient(baseURL: server, key: key).createDeviceKey(name: name) else { return }
        try? store.save(Connection(baseURL: server, key: minted.key))
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func revoke() async {
        let store = SharedKeychain.widgetStore
        if let saved = try? store.load() { try? await KinwallClient(saved).revokeOwnKey() }
        try? store.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    @MainActor private static func deviceName() -> String { UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone" }
}
