import SwiftUI
import UserNotifications
import WatchKit
import KinwallKit

/// Haptic transition warnings on the wrist: the Watch's person's transition reminders (set by an
/// admin in Kinwall) as local notifications, scheduled on the Watch itself from their events, like
/// the iPhone's leave-by Live Activity. No push: they're rescheduled whenever the app opens and on
/// the Watch's background refresh (about every 30 minutes, when watchOS allows).
///
/// Limits: watchOS keeps 64 pending notifications (48 are used); a warning for an event added
/// elsewhere only arrives once the Watch has refreshed since; and in the background watchOS plays
/// its own notification haptic. The distinct pattern (three rising taps) plays when the app is
/// frontmost (a raised wrist within the app, or right after a tap on the notification).
@MainActor
enum Transitions {
    nonisolated static let prefix = "tw:"
    static let refreshTask = "transitions"

    static func refresh(_ client: KinwallClient) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let person = UserDefaults.standard.string(forKey: "person") ?? "" // chosen on My chores
        guard !person.isEmpty,
              let members = try? await client.members(),
              let events = try? await client.events(from: .now, to: .now.addingTimeInterval(24 * 3600)) else { return }
        let config = members.first { $0.id == person }?.transitionReminders
        let warnings = TransitionWarnings.schedule(events: events, member: person, config: config, now: .now)
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        for w in warnings {
            let content = UNMutableNotificationContent()
            content.title = w.leave ? "Leave for \(w.title) in \(w.minutes) min" : "\(w.title) in \(w.minutes) min"
            content.body = w.leave ? "Leave by \(w.target.formatted(date: .omitted, time: .shortened))" : "Starts at \(w.target.formatted(date: .omitted, time: .shortened))"
            content.sound = .default
            content.categoryIdentifier = "transition"
            content.threadIdentifier = "transition"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, w.fireAt.timeIntervalSinceNow), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: w.id, content: content, trigger: trigger))
        }
    }

    /// Three rising taps: distinct from the Watch's usual notification tap.
    static func playWarning() {
        Task { @MainActor in
            for _ in 0..<3 {
                WKInterfaceDevice.current().play(.directionUp)
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    static func scheduleBackgroundRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: .now.addingTimeInterval(30 * 60), userInfo: refreshTask as NSString) { _ in }
    }
}

/// Plays the transition pattern when a warning arrives while the app is frontmost, and shows it as usual.
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        if notification.request.identifier.hasPrefix(Transitions.prefix) { await Transitions.playWarning() }
        return [.banner, .sound]
    }
}
