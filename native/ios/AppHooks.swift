import AppIntents
import UIKit

/// The app delegate's calls into our native code (plugins/withKinwallNative.js adds them to the
/// generated AppDelegate): Siri's parameter lists.
enum AppHooks {
    /// Siri learns the family's list, store, people and chore names (SiriIntents.swift entities)
    /// for its phrases; again whenever the app comes back, since they change.
    static func launched() {
        KinwallShortcuts.updateAppShortcutParameters()
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            KinwallShortcuts.updateAppShortcutParameters()
        }
    }

}
