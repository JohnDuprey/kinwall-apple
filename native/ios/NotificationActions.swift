internal import ExpoNotifications
import KinwallKit
import UIKit
import UserNotifications
import WidgetKit

/// The buttons on the app's reminders (src/reminders.ts sets the categories): Snooze on an event
/// reminder, Taken and Snooze on a medicine reminder, Done on the chore nudge. They run here, in the
/// background without opening the app, with the widgets' own key from the shared Keychain group:
/// the medicine buttons are the Live Activity's MarkDoseActivityIntent (LiveActivityIntents.swift),
/// Done is the Chores widget's call. Open, and a tap, go to the page (src/App.tsx).
///
/// A snooze is a copy of the reminder 10 minutes later (id "snz:…", which a refresh leaves be); a
/// medicine's snooze tells the server too, like the Live Activity's. If Taken or Done can't be
/// saved (offline, signed out), the reminder comes straight back saying so, so nothing is lost.
final class NotificationActions: NotificationDelegate {
    static let shared = NotificationActions()
    /// At launch (AppHooks), before a button that launched the app in the background is delivered.
    static func start() { NotificationCenterManager.shared.addDelegate(shared) }

    func didReceive(_ response: UNNotificationResponse, completionHandler: @escaping () -> Void) -> Bool {
        let action = response.actionIdentifier
        guard ["snooze", "taken", "done"].contains(action) else { return false }
        let request = response.notification.request
        Task { @MainActor in
            // expo-notifications completes the response right away; this keeps the call alive.
            let task = TaskBox()
            task.id = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(task.id) }
            let saved = await Self.perform(action, request.content.userInfo)
            if action == "snooze" { await Self.again(request, in: 10 * 60, note: nil) }
            else if !saved { await Self.again(request, in: 1, note: "Didn't save. Try again, or open Kinwall.") }
            else { WidgetCenter.shared.reloadAllTimelines() }
            UIApplication.shared.endBackgroundTask(task.id)
        }
        return true
    }

    /// The server's side of the button; true when there's nothing to tell it.
    private static func perform(_ action: String, _ info: [AnyHashable: Any]) async -> Bool {
        do {
            if let med = info["medicationId"] as? String, let date = info["date"] as? String, let time = info["time"] as? String {
                _ = try await MarkDoseActivityIntent(medicationId: med, date: date, time: time, action: action == "taken" ? "taken" : "snooze").perform()
            } else if action == "done", let chore = info["choreId"] as? String, let date = info["date"] as? String {
                guard let connection = try SharedKeychain.widgetStore.load() else { return false }
                try await KinwallClient(connection).complete(chore: chore, on: date)
            }
            return true
        } catch { return false }
    }

    private static func again(_ r: UNNotificationRequest, in seconds: TimeInterval, note: String?) async {
        guard let content = r.content.mutableCopy() as? UNMutableNotificationContent else { return }
        if let note { content.subtitle = note }
        let id = r.identifier.hasPrefix("snz:") ? r.identifier : "snz:" + r.identifier
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)))
    }
}

private final class TaskBox: @unchecked Sendable { var id = UIBackgroundTaskIdentifier.invalid }
