import Foundation
import UserNotifications
import BackgroundTasks
import KinwallKit

/// Event reminders as local notifications (docs/WIDGETS-AND-WATCH.md): the app can't receive the
/// server's web push, so it schedules the same reminders itself from the event list, using each
/// event's own reminder times (or the household default the server fills in). Rescheduled whenever
/// the app opens or goes to the background, and by a background refresh a few times a day.
enum Reminders {
    static let refreshTask = "family.kinwall.app.reminders"
    private static let prefix = "rem:"
    /// iOS keeps at most 64 pending notifications per app; leave room for anything else.
    private static let cap = 60
    /// How far ahead to schedule. Refreshes happen well within this.
    private static let horizon: TimeInterval = 48 * 3600

    /// Asks once; later calls return the saved answer without a prompt.
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func refresh() async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional,
              let connection = try? SharedKeychain.widgetStore.load() else { return }
        let now = Date()
        // ponytail: fetch failure keeps the reminders already scheduled; they may be stale until the next refresh.
        guard let events = try? await KinwallClient(connection).events(from: now.addingTimeInterval(-3600), to: now.addingTimeInterval(horizon)) else { return }

        let requests = events.flatMap { requests(for: $0, after: now) }
            .sorted { $0.fire < $1.fire }
            .prefix(cap)

        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        for r in requests { try? await center.add(r.request) }
    }

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTask)
        request.earliestBeginDate = Date().addingTimeInterval(4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Sign-out: nothing should fire for a household this device no longer belongs to.
    static func clear() async {
        let center = UNUserNotificationCenter.current()
        let ids = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Building them (mirrors the server's reminder text in server/src/notify.ts)

    private static func requests(for e: EventInstance, after now: Date) -> [(fire: Date, request: UNNotificationRequest)] {
        guard let minutes = e.reminders, !minutes.isEmpty else { return [] }
        let start = e.startDate ?? localMidnight(e.start)
        guard let start else { return [] }
        let leave = e.remindBeforeLeave ? e.leaveDate : nil
        let anchor = leave ?? start
        return minutes.compactMap { m in
            let fire = anchor.addingTimeInterval(-Double(m) * 60)
            guard fire > now, fire <= now.addingTimeInterval(horizon) else { return nil }
            let content = UNMutableNotificationContent()
            content.title = e.title
            let time = e.allDay ? "All day" : start.formatted(date: .omitted, time: .shortened)
            let first = leave.map { "Leave by \($0.formatted(date: .omitted, time: .shortened)) for \(e.title) · starts \(time)" }
                ?? "\(when(m)) · \(time)"
            content.body = [first, e.location.map { "📍 \($0.replacingOccurrences(of: "\n", with: ", "))" }].compactMap { $0 }.joined(separator: "\n")
            content.sound = .default
            content.threadIdentifier = "event:\(e.id)"
            content.userInfo = ["route": "calendar?event=\(escape(e.id))&at=\(escape(e.start))"] // tap opens this event
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
            let id = "\(prefix)\(e.id):\(e.start):\(m)"
            return (fire, UNNotificationRequest(identifier: id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }

    private static func when(_ m: Int) -> String {
        if m == 0 { return "Now" }
        if m % 60 == 0 { return "In \(m / 60) hour\(m == 60 ? "" : "s")" }
        return "In \(m) minutes"
    }

    /// All-day events start at midnight on this device.
    // ponytail: device timezone, not the household's; differs only when the phone travels.
    private static func localMidnight(_ day: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: day)
    }

    private static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? s
    }
}

/// Shows reminders while the app is open and turns a tap into a route in the web app.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationRouter()
    @MainActor private var onOpen: ((String) -> Void)?
    @MainActor private var pending: String? // tapped before the app's view was ready (a cold launch)

    @MainActor func listen(_ open: @escaping (String) -> Void) {
        onOpen = open
        if let pending { self.pending = nil; open(pending) }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let route = response.notification.request.content.userInfo["route"] as? String else { return }
        await MainActor.run { if let onOpen { onOpen(route) } else { pending = route } }
    }
}
