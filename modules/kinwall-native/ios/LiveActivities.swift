import ActivityKit
import Foundation

/// The app's Live Activities (a cooking timer, a shopping trip, the next leave-by or start-prep
/// time, a medicine that's due), started, updated and ended from the web app's messages (src/liveActivities.ts, and
/// web/src/liveActivity.ts in the kinwall repo, which decides what they say). One of each kind at a
/// time. The deployment target is iOS 17, so ActivityKit and its interactive buttons are always
/// there; Live Activities turned off in Settings make all of this a no-op.
enum LiveActivities {
    typealias Attributes = KinwallActivityAttributes

    /// Apple push is only signed in with a paid team: the plugin sets KinwallPush when a build has
    /// the push entitlement (KINWALL_PUSH=1 at prebuild, docs/PLAN.md). Without it no tokens are asked for.
    static var pushEnabled: Bool { Bundle.main.object(forInfoDictionaryKey: "KinwallPush") as? Bool ?? false }

    /// The web app's kind ("leaveBy") and the attributes' ("leave" or "prep").
    static func group(_ kind: String) -> Set<String> { kind == "leaveBy" ? ["leave", "prep"] : [kind] }
    static func running(_ kind: String) -> [Activity<Attributes>] {
        Activity<Attributes>.activities.filter { group(kind).contains($0.attributes.kind) && $0.activityState == .active }
    }

    /// Starts the kind's activity, or updates the one showing. What an activity is about (its
    /// attributes) can't change, so another recipe, store or event ends the old one first.
    static func set(kind: String, json: String, colors: Attributes.Colors?, onToken: @escaping ([String: Any]) -> Void) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, let (attributes, state, stale) = try content(kind: kind, json: json, colors: colors) else { return }
        let next = ActivityContent(state: state, staleDate: stale)
        for activity in running(kind) {
            if same(activity.attributes, attributes) { await activity.update(next); return }
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        let push = pushEnabled && attributes.activity != nil
        let activity = try Activity.request(attributes: attributes, content: next, pushType: push ? .token : nil)
        if push { watchToken(activity, onToken) }
    }

    static func end(kind: String) async {
        for activity in running(kind) { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    static func endAll() async {
        for activity in Activity<Attributes>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Ones the page can't end because the app wasn't open: a leave-by past its end, a cooking
    /// timer that rang half an hour ago. Called when the app comes back and from background refresh.
    static func endStale(now: Date = .now) async {
        for activity in Activity<Attributes>.activities where activity.activityState == .active {
            let a = activity.attributes, s = activity.content.state
            let over = (a.endsAt.map { $0 <= now } ?? false) || (a.kind == "cooking" && (s.date.map { $0.addingTimeInterval(30 * 60) <= now } ?? false))
            if over { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// With push (a paid team): the push-to-start token, and each leave-by activity's update token
    /// (ones the server started too), for the app to register with the server.
    static func watchPush(_ onToken: @escaping ([String: Any]) -> Void) {
        guard pushEnabled else { return }
        if #available(iOS 17.2, *) {
            Task { for await data in Activity<Attributes>.pushToStartTokenUpdates { onToken(["kind": "start", "token": hex(data)]) } }
        }
        Task { for await activity in Activity<Attributes>.activityUpdates where activity.attributes.activity != nil { watchToken(activity, onToken) } }
    }

    private static func watchToken(_ activity: Activity<Attributes>, _ onToken: @escaping ([String: Any]) -> Void) {
        Task {
            for await data in activity.pushTokenUpdates {
                var token: [String: Any] = ["kind": "update", "token": hex(data), "activity": activity.attributes.activity ?? ""]
                if let ends = activity.attributes.endsAt { token["endsAt"] = ISO8601DateFormatter().string(from: ends) }
                onToken(token)
            }
        }
    }

    private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    private static func same(_ a: Attributes, _ b: Attributes) -> Bool {
        a.kind == b.kind && a.name == b.name && a.listId == b.listId && a.eventId == b.eventId && a.activity == b.activity && a.colors == b.colors && a.dose == b.dose
    }

    // MARK: - The web app's payloads (web/src/liveActivity.ts)

    private struct Cooking: Decodable { let recipe: String; let timer: String; let step: String; let endsAt: Double; let done: Bool; let more: Int }
    private struct Shopping: Decodable { let listId: String; let store: String; let left: Int; let next: Attributes.Entry?; let upcoming: [Attributes.Entry] }
    private struct Medication: Decodable { let medicationId: String; let date: String; let time: String; let label: String; let headline: String; let windowEndsAt: String; let stage: String }
    private struct LeaveBy: Decodable { let activity: String; let eventId: String; let title: String; let prep: Bool; let at: String; let endsAt: String; let headline: String; let urgent: String }

    private static func date(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    static func content(kind: String, json: String, colors: Attributes.Colors?) throws -> (Attributes, Attributes.ContentState, Date?)? {
        let data = Data(json.utf8), decoder = JSONDecoder()
        switch kind {
        case "cooking":
            let p = try decoder.decode(Cooking.self, from: data)
            let ends = Date(timeIntervalSince1970: p.endsAt / 1000)
            return (Attributes(kind: "cooking", name: p.recipe, colors: colors), .init(title: p.timer, detail: p.step, date: ends, count: p.more, done: p.done), p.done ? nil : ends)
        case "shopping":
            let p = try decoder.decode(Shopping.self, from: data)
            return (Attributes(kind: "shopping", name: p.store, listId: p.listId, colors: colors), .init(title: p.next?.title ?? "", detail: p.next?.aisle, count: p.left, itemId: p.next?.id, queue: p.upcoming), nil)
        case "leaveBy":
            let p = try decoder.decode(LeaveBy.self, from: data)
            guard let at = date(p.at) else { return nil }
            let attributes = Attributes(kind: p.prep ? "prep" : "leave", name: p.title, eventId: p.eventId, activity: p.activity, endsAt: date(p.endsAt), colors: colors)
            return (attributes, .init(title: p.headline, detail: p.urgent, date: at), at)
        case "medication":
            // The label is the web app's own (generic unless the device opted into names): shown as is.
            let p = try decoder.decode(Medication.self, from: data)
            guard let until = date(p.windowEndsAt) else { return nil }
            let attributes = Attributes(kind: "medication", name: p.label, endsAt: until, colors: colors, dose: .init(medicationId: p.medicationId, date: p.date, time: p.time))
            return (attributes, .init(title: p.headline, detail: p.stage, date: until), until)
        default:
            return nil
        }
    }
}
