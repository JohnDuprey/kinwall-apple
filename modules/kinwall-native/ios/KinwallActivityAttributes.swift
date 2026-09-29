import ActivityKit
import Foundation

// The Live Activities' data, shared by the app (this module starts and updates them) and the
// widget extension (targets/widgets/LiveActivities.swift draws them; plugins/withKinwallNative.js
// compiles this same file into it). ActivityKit matches the two by the type's name, and the
// server's push (kinwall server/src/notify.ts runLiveActivities) sends this exact JSON, so keep all
// three in step. Dates in a content state decode as seconds since 2001 (Swift's default).

public struct KinwallActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Cooking: the timer's name. Shopping: the item to get now ("" when all done). Leave / prep: the headline.
        /// Medication: whose it is.
        public var title: String
        /// Cooking: "Step 3 · Simmer". Shopping: that item's aisle. Leave / prep: the "now" line.
        /// Medication: "due" or "late" (still inside its window), or "snoozed".
        public var detail: String?
        /// Cooking: when the timer's up. Leave / prep: the leave-by or start-prep time. Medication: the
        /// end of its window (or, snoozed, when it's back).
        public var date: Date?
        /// Cooking: other timers running. Shopping: items left.
        public var count: Int
        /// Cooking: the timer rang.
        public var done: Bool
        /// Shopping: the item to get now, then the few after it, so "Got it" can move on without the
        /// app's page and the activity can say what's after it.
        public var itemId: String?
        public var queue: [Entry]?

        public init(title: String, detail: String? = nil, date: Date? = nil, count: Int = 0, done: Bool = false, itemId: String? = nil, queue: [Entry]? = nil) {
            self.title = title; self.detail = detail; self.date = date; self.count = count; self.done = done; self.itemId = itemId; self.queue = queue
        }
    }

    public struct Entry: Codable, Hashable {
        public var id: String
        public var title: String
        public var aisle: String?
        public init(id: String, title: String, aisle: String?) { self.id = id; self.title = title; self.aisle = aisle }
    }

    /// The family's colors when the app has them (its saved appearance), as #RRGGBB; nil draws Kinwall's.
    public struct Colors: Codable, Hashable {
        public var bg: String
        public var fg: String
        public var accent: String
        public init(bg: String, fg: String, accent: String) { self.bg = bg; self.fg = fg; self.accent = accent }
    }

    /// Medication: the dose Taken and Snooze mark (POST /api/medications/{id}/doses).
    public struct Dose: Codable, Hashable {
        public var medicationId: String
        public var date: String
        public var time: String
        public init(medicationId: String, date: String, time: String) { self.medicationId = medicationId; self.date = date; self.time = time }
    }

    /// "cooking", "shopping", "leave", "prep" or "medication".
    public var kind: String
    /// The recipe, the store, the event, or the medicine's label (the web app's, generic unless the
    /// device opted into names).
    public var name: String
    public var listId: String?
    public var eventId: String?
    /// Leave / prep: the server's name for it ("leaveBy:<event>@<start>"), so its push token is registered under it.
    public var activity: String?
    /// Leave / prep: when it should go (the event's start, or a few minutes after the time).
    public var endsAt: Date?
    public var colors: Colors?
    public var dose: Dose?

    public init(kind: String, name: String, listId: String? = nil, eventId: String? = nil, activity: String? = nil, endsAt: Date? = nil, colors: Colors? = nil, dose: Dose? = nil) {
        self.kind = kind; self.name = name; self.listId = listId; self.eventId = eventId; self.activity = activity; self.endsAt = endsAt; self.colors = colors; self.dose = dose
    }
}
