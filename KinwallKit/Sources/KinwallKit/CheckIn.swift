import Foundation

// The daily check-in (Temp check) and the energy battery, for the widgets and the Watch. Health
// data: only ever read with a key that belongs to the person (the server refuses shared walls and
// other members' devices), never logged, and kept only as long as a widget shows it.

/// GET /api/me: this key's scope and owner (a member id, "shared", or nil).
public struct Me: Codable, Hashable, Sendable {
    public let scope: String
    public let owner: String?
    /// The member this device belongs to, if it's someone's own (not a shared wall).
    public var person: String? { owner.flatMap { $0 == "shared" || $0.isEmpty ? nil : $0 } }
}

/// GET /api/members/{id}/temp-check (today).
public struct TempCheck: Codable, Hashable, Sendable {
    public struct Settings: Codable, Hashable, Sendable {
        public let on: Bool
        public let sleep: Bool
        public let feelings: Bool
        public let goal: Bool
        public let evening: Bool
        public let eveningTime: String
        public let battery: Bool
    }
    public struct Answered: Codable, Hashable, Sendable {
        public let sleep: Bool
        public let feelings: Bool
        public let goal: Bool
        public let followup: Bool
        public let drained: Bool
    }
    public let memberId: String
    public let date: String
    public let settings: Settings
    public let `private`: Bool
    public let goal: String?
    public let answered: Answered
    public let followupOpen: Bool
    public let drainedOpen: Bool
    public let custom: [String]?

    public enum Step: String, Sendable { case off, sleep, feelings, goal, followup, drained, done }

    /// What to ask next. Evening (the goal check or "How drained?" showing): those, then done.
    /// Otherwise the morning questions they get, in order.
    public var step: Step {
        guard settings.on else { return .off }
        if followupOpen && !answered.followup { return .followup }
        if drainedOpen && !answered.drained { return .drained }
        if followupOpen || drainedOpen { return .done }
        if settings.sleep && !answered.sleep { return .sleep }
        if settings.feelings && !answered.feelings { return .feelings }
        if settings.goal && !answered.goal { return .goal }
        return .done
    }

    public static let sleepAnswers: [(key: String, emoji: String, label: String)] = [("great", "😄", "Great"), ("good", "🙂", "Good"), ("ok", "😐", "OK"), ("poorly", "😕", "Poorly"), ("terrible", "😫", "Terrible")]
    public static let followupAnswers: [(key: String, label: String)] = [("yes", "Yes"), ("partly", "Partly"), ("no", "Not today")]
    public static let drainedAnswers: [(key: String, emoji: String, label: String)] = [("full", "😊", "Full"), ("ok", "🙂", "OK"), ("low", "😌", "Low"), ("empty", "😴", "Empty")]
    static let feelings = ["great", "good", "fine", "ok", "bad", "awful", "tired", "sore"]

    /// A few feelings to tap: their own ("Other" answers) first, then the built-ins, no repeats.
    public static func feelingChoices(custom: [String], limit: Int) -> [String] {
        let own = custom.filter { !feelings.contains($0.lowercased()) }
        var seen = Set<String>(), out: [String] = []
        for f in own + feelings where seen.insert(f.lowercased()).inserted { out.append(f) }
        return Array(out.prefix(limit))
    }
}

/// PUT /api/members/{id}/temp-check: only the fields set are sent.
public struct TempCheckAnswer: Encodable, Sendable {
    public var sleep: String?
    public var feelings: [String]?
    public var followup: Followup?
    public var drained: String?
    public struct Followup: Encodable, Sendable {
        public let outcome: String
        public let helped: String? = nil, hindered: String? = nil, next: String? = nil
        public init(outcome: String) { self.outcome = outcome }
    }
    public init(sleep: String? = nil, feelings: [String]? = nil, followup: Followup? = nil, drained: String? = nil) {
        self.sleep = sleep; self.feelings = feelings; self.followup = followup; self.drained = drained
    }
}

/// GET /api/members/{id}/battery.
public struct Battery: Codable, Hashable, Sendable {
    public struct Reason: Codable, Hashable, Sendable { public let text: String; public let points: Int }
    public struct Day: Codable, Hashable, Sendable {
        public let date: String
        public let forecast: Bool
        public let level: Int
        public let reasons: [Reason]
    }
    public struct Warning: Codable, Hashable, Sendable { public let date: String; public let text: String }
    public let on: Bool
    public let today: String
    public let days: [Day]
    public let warnings: [Warning]

    /// Calm words for a level, as the web app says them (web/src/battery.ts levelWord).
    public static func word(_ level: Int) -> String { level >= 75 ? "Full" : level >= 50 ? "Good" : level >= 25 ? "Getting low" : "Running low" }

    public struct Summary: Hashable, Sendable {
        public let level: Int
        /// "62% · Good by this evening"
        public let line: String
        /// The two biggest reasons with points behind today's number.
        public let reasons: [String]
        /// Tomorrow's heads-up, if there is one.
        public let headsUp: String?
    }

    /// Today, or nil while the battery is off.
    public var summary: Summary? {
        guard on, let day = days.first(where: { $0.date == today }) else { return nil }
        let tomorrow = days.first { $0.date > today }?.date
        return Summary(level: day.level, line: "\(day.level)% · \(Self.word(day.level)) by this evening",
                       reasons: Array(day.reasons.filter { $0.points != 0 }.prefix(2).map(\.text)),
                       headsUp: warnings.first { $0.date == today || $0.date == tomorrow }?.text)
    }
}

extension KinwallClient {
    public func me() async throws -> Me { try await send("GET", "api/me") }
    public func tempCheck(_ memberId: String) async throws -> TempCheck { try await send("GET", "api/members/\(memberId)/temp-check") }
    public func answer(_ memberId: String, _ answer: TempCheckAnswer) async throws {
        try await sendIgnoringBody("PUT", "api/members/\(memberId)/temp-check", body: answer)
    }
    public func battery(_ memberId: String) async throws -> Battery { try await send("GET", "api/members/\(memberId)/battery") }
}
