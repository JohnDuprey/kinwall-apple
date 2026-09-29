import Foundation

// Pure helpers over the Board and events, shared by Siri ("What's on today") and the Watch
// (transition warnings). Tested in PlanningTests.

/// What's left of today: timed events that haven't ended plus all-day ones, and chores left.
public struct TodaySummary: Sendable {
    public let events: [BoardEvent]
    public let choresLeft: Int
    public let choresTotal: Int
    /// One or two sentences for Siri to say.
    public let spoken: String

    public init(board: Board, now: Date = .now, time: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }) {
        let today = board.events.filter { $0.date == board.today && ($0.allDay || ($0.endDate ?? .distantFuture) > now) }
        events = today.filter(\.allDay) + today.filter { !$0.allDay }.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
        choresLeft = board.chores.reduce(0) { $0 + $1.remaining }
        choresTotal = board.chores.reduce(0) { $0 + $1.total }
        let lines = events.map { e -> String in
            guard let start = e.startDate else { return "\(e.title), all day" }
            var line = "\(e.title) at \(time(start))"
            if let leave = e.leaveDate, leave > now { line += ", leave by \(time(leave))" }
            return line
        }
        let calendar = lines.isEmpty ? "Nothing else on the calendar today." : "Today: \(lines.joined(separator: "; "))."
        let chores = choresTotal == 0 ? "" : choresLeft == 0 ? " All chores done." : " \(choresLeft) chore\(choresLeft == 1 ? "" : "s") left."
        spoken = calendar + chores
    }
}

/// A person's transition reminders (GET /api/members, set by an admin): warnings a few minutes
/// before their events, and whether to count back from the leave-by time.
public struct TransitionReminders: Codable, Hashable, Sendable {
    public struct Repeat: Codable, Hashable, Sendable {
        public let every: Int
        public let within: Int
        public init(every: Int, within: Int) { self.every = every; self.within = within }
    }
    public let on: Bool
    public let minutes: [Int]
    public let `repeat`: Repeat?
    public let leaveBy: Bool
    public init(on: Bool, minutes: [Int], repeat: Repeat?, leaveBy: Bool) { self.on = on; self.minutes = minutes; self.repeat = `repeat`; self.leaveBy = leaveBy }

    /// Picked minutes plus every `repeat.every` in the last `repeat.within`, 1 to 120, latest first
    /// (the server's transitionTimes, server/src/notify.ts).
    public static func times(_ minutes: [Int], repeat: Repeat?) -> [Int] {
        var all = Set(minutes)
        if let r = `repeat`, r.every > 0 { for m in stride(from: r.every, through: r.within, by: r.every) { all.insert(m) } }
        return all.filter { (1...120).contains($0) }.sorted(by: >)
    }
}

/// One warning to schedule on the device: `minutes` before the leave-by time (`leave`) or the start.
public struct TransitionWarning: Hashable, Sendable {
    public let id: String
    public let fireAt: Date
    public let minutes: Int
    public let leave: Bool
    public let title: String
    public let target: Date
}

public enum TransitionWarnings {
    /// The warnings still ahead for `member`'s timed events (tagged with them, or nobody), soonest
    /// first, at most `limit` (watchOS keeps 64 pending notifications). Like the server's push
    /// (runTransitionReminders): counts back from the leave-by time when `leaveBy` is on and the
    /// event has travel time, else from the start. Meal prep times aren't in /api/events, so a
    /// meal counts from its start.
    public static func schedule(events: [EventInstance], member: String, config: TransitionReminders?, now: Date, limit: Int = 48) -> [TransitionWarning] {
        guard let config, config.on else { return [] }
        let times = TransitionReminders.times(config.minutes, repeat: config.repeat)
        let warnings = events.flatMap { e -> [TransitionWarning] in
            guard !e.allDay, let start = e.startDate, e.memberIds.isEmpty || e.memberIds.contains(member) else { return [] }
            let leave = config.leaveBy ? e.leaveDate : nil
            let target = leave ?? start
            return times.compactMap { t in
                let fire = target.addingTimeInterval(Double(-t * 60))
                return fire > now ? TransitionWarning(id: "tw:\(e.id):\(e.start):\(t)", fireAt: fire, minutes: t, leave: leave != nil, title: e.title, target: target) : nil
            }
        }
        return Array(warnings.sorted { $0.fireAt < $1.fireAt }.prefix(limit))
    }
}

