import AppIntents
import CoreSpotlight
import UIKit
internal import KinwallNative

/// The app delegate's calls into our native code (plugins/withKinwallNative.js adds them to the
/// generated AppDelegate): Siri's parameter lists, and a tapped Spotlight result.
enum AppHooks {
    /// Siri learns the family's list, store, people and chore names (SiriIntents.swift entities)
    /// for its phrases; again whenever the app comes back, since they change.
    static func launched() {
        KinwallShortcuts.updateAppShortcutParameters()
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            KinwallShortcuts.updateAppShortcutParameters()
        }
    }

    /// A Spotlight result (modules/kinwall-native Spotlight.swift): its identifier is the app link to open.
    static func open(_ activity: NSUserActivity) -> Bool {
        guard activity.activityType == CSSearchableItemActionType,
              let link = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String, link.hasPrefix("family.kinwall.app:/open?") else { return false }
        PendingLink.open(link)
        return true
    }
}
