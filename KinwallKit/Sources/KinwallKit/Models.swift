import Foundation

// The subset of Kinwall's REST shapes the apps use (see the server's /openapi.json).
// Fields the apps don't read are left out; unknown fields are ignored when decoding.

public struct Member: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let color: String
    public let avatar: String?
    public let pointsToday: Int
    public let pointsWeek: Int
    public let balance: Int
}

public struct Settings: Codable, Hashable, Sendable {
    public let familyName: String
    public let timezone: String?
    public let weekStart: Int
    public let colorScheme: String?
}

/// A chore as it stands on one day (GET /api/chores/day).
public struct ChoreDay: Codable, Identifiable, Hashable, Sendable {
    public struct Checklist: Codable, Hashable, Sendable {
        public let listId: String
        public let name: String
        public let total: Int
        public let done: Int
        public var isFinished: Bool { done >= total }
    }
    public let id: String
    public let title: String
    public let emoji: String?
    /// nil = an "Anyone" chore.
    public let memberId: String?
    public let points: Int
    public let completed: Bool
    public let completedBy: String?
    public let checklist: Checklist?
    public var isAnyone: Bool { memberId == nil }
}

public struct FamilyList: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case todo, shopping, reusable }
    public let id: String
    public let name: String
    public let emoji: String?
    public let kind: Kind
    public let archived: Bool
    public let itemCount: Int
    public let openCount: Int
}

public struct ListItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let listId: String
    public let title: String
    public let notes: String?
    public let quantity: String?
    public let category: String?
    public let memberId: String?
    public let dueDate: String?
    public let priority: String?
    public let done: Bool
}

/// GET /api/lists/{id}: the list and its items (in the list's own sort order).
public struct ListDetail: Codable, Hashable, Sendable {
    public let list: FamilyList
    public let items: [ListItem]
}

// ---- Pairing (TV-style: the app shows a code, an admin approves it in Kinwall) ----

public struct PairStart: Codable, Sendable {
    public let pairingId: String
    public let code: String
    public let pollToken: String
    public let expiresAt: String
}

public enum PairPoll: Decodable, Sendable, Equatable {
    case pending
    case approved(key: String)

    private enum Keys: String, CodingKey { case status, key }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        switch try c.decode(String.self, forKey: .status) {
        case "approved": self = .approved(key: try c.decode(String.self, forKey: .key))
        default: self = .pending
        }
    }
}

// ---- The Board (GET /api/board): today and the days ahead, for widgets and the watch ----

public struct BoardEvent: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    /// ISO instants for timed events; YYYY-MM-DD for all-day ones.
    public let start: String
    public let end: String
    public let allDay: Bool
    public let memberIds: [String]
    public let color: String?
    public let location: String?
    /// When to leave for it (ISO), if it has travel time.
    public let leaveAt: String?
    /// The household-local day it's listed under.
    public let date: String

    public init(id: String, title: String, start: String, end: String, allDay: Bool, memberIds: [String], color: String?, location: String?, leaveAt: String?, date: String) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.allDay = allDay
        self.memberIds = memberIds; self.color = color; self.location = location; self.leaveAt = leaveAt; self.date = date
    }

    public var startDate: Date? { allDay ? nil : ISO8601.parse(start) }
    public var endDate: Date? { allDay ? nil : ISO8601.parse(end) }
    public var leaveDate: Date? { leaveAt.flatMap(ISO8601.parse) }
}

public struct BoardItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let listId: String
    public let title: String
    public let listName: String
    public let listEmoji: String?
    public let dueDate: String?
    public let overdue: Bool
    public let memberId: String?
}

public struct Board: Codable, Hashable, Sendable {
    public struct ChoreProgress: Codable, Hashable, Sendable {
        /// nil = the Anyone chores.
        public let memberId: String?
        public let name: String?
        public let avatar: String?
        public let color: String?
        public let remaining: Int
        public let total: Int
        public init(memberId: String?, name: String?, avatar: String?, color: String?, remaining: Int, total: Int) {
            self.memberId = memberId; self.name = name; self.avatar = avatar; self.color = color; self.remaining = remaining; self.total = total
        }
    }
    public let today: String
    public let events: [BoardEvent]
    public let items: [BoardItem]
    public let chores: [ChoreProgress]

    public init(today: String, events: [BoardEvent], items: [BoardItem], chores: [ChoreProgress]) {
        self.today = today; self.events = events; self.items = items; self.chores = chores
    }

    /// Timed events today that haven't ended, soonest first; `now` is the first one under way.
    public func nowAndNext(at now: Date = .now) -> (now: BoardEvent?, next: BoardEvent?) {
        let today = events.filter { $0.date == self.today && !$0.allDay }
        let current = today.first { ($0.startDate ?? .distantFuture) <= now && now < ($0.endDate ?? .distantPast) }
        let next = today.filter { ($0.startDate ?? .distantPast) > now }.min { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        return (current, next)
    }
}

/// An event occurrence from GET /api/events, with what's needed to remind about it on the device.
public struct EventInstance: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    /// ISO instant for timed events; YYYY-MM-DD for all-day ones.
    public let start: String
    public let allDay: Bool
    public let location: String?
    public let memberIds: [String]
    /// Minutes before start (or before leaveAt when remindBeforeLeave) to remind; nil or [] = none.
    public let reminders: [Int]?
    public let leaveAt: String?
    public let remindBeforeLeave: Bool

    public init(id: String, title: String, start: String, allDay: Bool, location: String?, memberIds: [String], reminders: [Int]?, leaveAt: String?, remindBeforeLeave: Bool) {
        self.id = id; self.title = title; self.start = start; self.allDay = allDay; self.location = location
        self.memberIds = memberIds; self.reminders = reminders; self.leaveAt = leaveAt; self.remindBeforeLeave = remindBeforeLeave
    }

    public var startDate: Date? { allDay ? nil : ISO8601.parse(start) }
    public var leaveDate: Date? { leaveAt.flatMap(ISO8601.parse) }
}

enum ISO8601 {
    static func parse(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: s) ?? ISO8601DateFormatter().date(from: s)
    }
}
