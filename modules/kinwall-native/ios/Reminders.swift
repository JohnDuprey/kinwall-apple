import Foundation
import UserNotifications

/// The app's local reminders (src/reminders.ts schedules them with expo-notifications), finished
/// with what expo-notifications can't set: the Kinwall Focus filter's tag (`data.focus`, "others"
/// for someone else's event, which "Only my reminders" hides: native/ios/FocusFilter.swift) and,
/// for leave-by and medicine (`data.urgent`), Time Sensitive, so they break through a Focus. Time
/// Sensitive needs its entitlement, which the Personal Team's profile doesn't carry, so only a
/// build prebuilt with KINWALL_TIME_SENSITIVE=1 or KINWALL_PUSH=1 (plugins/withKinwallNative.js)
/// sets it; otherwise they stay active notifications.
enum Reminders {
    static var timeSensitive: Bool { Bundle.main.object(forInfoDictionaryKey: "KinwallTimeSensitive") as? Bool ?? false }

    static func tag() async {
        let center = UNUserNotificationCenter.current()
        for r in await center.pendingNotificationRequests() where r.identifier.hasPrefix("rem:") {
            let focus = r.content.userInfo["focus"] as? String
            let level: UNNotificationInterruptionLevel = timeSensitive && r.content.userInfo["urgent"] as? Bool == true ? .timeSensitive : r.content.interruptionLevel
            guard focus != r.content.filterCriteria || level != r.content.interruptionLevel,
                  let content = r.content.mutableCopy() as? UNMutableNotificationContent else { continue }
            content.filterCriteria = focus
            content.interruptionLevel = level
            // Adding it again under its id replaces it; a date trigger (a time interval) is re-aimed at its date.
            var trigger = r.trigger
            if let t = trigger as? UNTimeIntervalNotificationTrigger, !t.repeats {
                guard let next = t.nextTriggerDate(), next.timeIntervalSinceNow > 1 else { continue }
                trigger = UNTimeIntervalNotificationTrigger(timeInterval: next.timeIntervalSinceNow, repeats: false)
            }
            try? await center.add(UNNotificationRequest(identifier: r.identifier, content: content, trigger: trigger))
        }
    }
}
