import Foundation
import Testing
@testable import KinwallKit

// The pure helpers behind Siri's "What's on today" and the Watch's transition warnings.

nonisolated(unsafe) private let iso = ISO8601DateFormatter()
private func at(_ s: String) -> Date { iso.date(from: s)! }
private func ev(_ id: String, _ title: String, _ start: String, _ end: String, allDay: Bool = false, members: [String] = [], leave: String? = nil, date: String = "2026-09-29") -> BoardEvent {
    BoardEvent(id: id, title: title, start: start, end: end, allDay: allDay, memberIds: members, color: nil, location: nil, leaveAt: leave, date: date)
}

@Suite struct TodaySummaryTests {
    let now = at("2026-09-29T15:00:00Z")
    func board(_ events: [BoardEvent], chores: [Board.ChoreProgress] = []) -> Board { Board(today: "2026-09-29", events: events, items: [], chores: chores) }
    let time: (Date) -> String = { iso.string(from: $0) }

    @Test func listsWhatIsLeftTodayAndChores() {
        let b = board([
            ev("a", "Breakfast", "2026-09-29T12:00:00Z", "2026-09-29T13:00:00Z"), // over
            ev("b", "Soccer", "2026-09-29T16:00:00Z", "2026-09-29T17:00:00Z", leave: "2026-09-29T15:40:00Z"),
            ev("c", "Pizza night", "2026-09-29", "2026-09-30", allDay: true),
            ev("d", "Tomorrow thing", "2026-09-30T16:00:00Z", "2026-09-30T17:00:00Z", date: "2026-09-30"),
        ], chores: [.init(memberId: "m1", name: "Maya", avatar: nil, color: nil, remaining: 2, total: 3), .init(memberId: nil, name: nil, avatar: nil, color: nil, remaining: 1, total: 1)])
        let s = TodaySummary(board: b, now: now, time: time)
        #expect(s.events.map(\.title) == ["Pizza night", "Soccer"])
        #expect(s.choresLeft == 3)
        #expect(s.spoken == "Today: Pizza night, all day; Soccer at 2026-09-29T16:00:00Z, leave by 2026-09-29T15:40:00Z. 3 chores left.")
    }

    @Test func quietDay() {
        let s = TodaySummary(board: board([], chores: [.init(memberId: "m1", name: "Maya", avatar: nil, color: nil, remaining: 0, total: 2)]), now: now, time: time)
        #expect(s.spoken == "Nothing else on the calendar today. All chores done.")
    }

    @Test func oneChoreIsSingular() {
        let s = TodaySummary(board: board([], chores: [.init(memberId: nil, name: nil, avatar: nil, color: nil, remaining: 1, total: 1)]), now: now, time: time)
        #expect(s.spoken.hasSuffix("1 chore left."))
    }

    @Test func choresOffSaysNothingAboutChores() {
        var off = Features(); off.chores = false; off.lists = false
        let item = BoardItem(id: "i1", listId: "l1", title: "Pay the bill", listName: "To-dos", listEmoji: nil, dueDate: "2026-09-29", overdue: false, memberId: nil)
        let b = Board(today: "2026-09-29", events: [], items: [item], chores: [.init(memberId: "m1", name: "Maya", avatar: nil, color: nil, remaining: 2, total: 3)]).respecting(off)
        #expect(b.chores.isEmpty && b.items.isEmpty)
        #expect(TodaySummary(board: b, now: now, time: time).spoken == "Nothing else on the calendar today.")
        #expect(board([], chores: [.init(memberId: nil, name: nil, avatar: nil, color: nil, remaining: 1, total: 1)]).respecting(Features()).chores.count == 1, "on: kept")
    }
}

@Suite struct FeaturesTests {
    func settings(_ json: String) throws -> Settings { try JSONDecoder().decode(Settings.self, from: Data(json.utf8)) }

    @Test func olderServersHaveEverythingOn() throws {
        let s = try settings(#"{"familyName":"Our Family","timezone":null,"weekStart":0,"colorScheme":null}"#)
        #expect(s.features == nil && s.rewardsEnabled == nil)
        #expect(s.on == Features())
        #expect(s.on.chores && s.on.lists && s.on.checkIns)
    }

    @Test func missingAndUnknownSwitchesDontBreakDecoding() throws {
        let s = try settings(#"{"familyName":"F","weekStart":1,"features":{"chores":false,"lists":true,"meals":false,"somethingNew":false,"contacts":"odd"},"rewardsEnabled":false}"#)
        #expect(!s.on.chores && s.on.lists && !s.on.meals)
        #expect(s.on.checkIns, "missing: on")
        #expect(s.on.contacts, "not a boolean: on")
        #expect(s.rewardsEnabled == false)
    }
}

@Suite struct TransitionWarningTests {
    let now = at("2026-09-29T15:00:00Z")
    let me = "m1"
    func instance(_ id: String, _ start: String, members: [String] = [], leave: String? = nil, allDay: Bool = false) -> EventInstance {
        EventInstance(id: id, title: "Soccer", start: start, allDay: allDay, location: nil, memberIds: members, reminders: nil, leaveAt: leave, remindBeforeLeave: false)
    }

    @Test func timesAreDedupedLatestFirst() {
        #expect(TransitionReminders.times([10, 5], repeat: .init(every: 5, within: 15)) == [15, 10, 5])
        #expect(TransitionReminders.times([0, 200, 30], repeat: nil) == [30])
    }

    @Test func warnsBeforeLeavingForTheirEvents() {
        let cfg = TransitionReminders(on: true, minutes: [15, 5], repeat: nil, leaveBy: true)
        let w = TransitionWarnings.schedule(events: [
            instance("a", "2026-09-29T16:00:00Z", leave: "2026-09-29T15:40:00Z"), // untagged counts as everyone's
            instance("b", "2026-09-29T17:00:00Z", members: ["m2"]), // someone else's
            instance("c", "2026-09-29T15:10:00Z"), // 15 min warning already past, 5 min still ahead
            instance("d", "2026-09-29", allDay: true),
        ], member: me, config: cfg, now: now)
        #expect(w.map(\.fireAt) == [at("2026-09-29T15:05:00Z"), at("2026-09-29T15:25:00Z"), at("2026-09-29T15:35:00Z")])
        #expect(w.map(\.minutes) == [5, 15, 5])
        #expect(w[1].leave && !w[0].leave)
        #expect(w[1].id == "tw:a:2026-09-29T16:00:00Z:15")
    }

    @Test func leaveByOffCountsFromTheStart() {
        let cfg = TransitionReminders(on: true, minutes: [10], repeat: nil, leaveBy: false)
        let w = TransitionWarnings.schedule(events: [instance("a", "2026-09-29T16:00:00Z", leave: "2026-09-29T15:40:00Z")], member: me, config: cfg, now: now)
        #expect(w.map(\.fireAt) == [at("2026-09-29T15:50:00Z")])
        #expect(!w[0].leave)
    }

    @Test func offOrMissingSchedulesNothing() {
        let off = TransitionReminders(on: false, minutes: [10], repeat: nil, leaveBy: true)
        #expect(TransitionWarnings.schedule(events: [instance("a", "2026-09-29T16:00:00Z")], member: me, config: off, now: now).isEmpty)
        #expect(TransitionWarnings.schedule(events: [instance("a", "2026-09-29T16:00:00Z")], member: me, config: nil, now: now).isEmpty)
    }

    @Test func capsTheCount() {
        let cfg = TransitionReminders(on: true, minutes: [1, 2, 3], repeat: nil, leaveBy: true)
        let many = (0..<40).map { instance("e\($0)", iso.string(from: now.addingTimeInterval(Double($0 + 1) * 3600))) }
        #expect(TransitionWarnings.schedule(events: many, member: me, config: cfg, now: now, limit: 50).count == 50)
    }

    @Test func decodesAMemberWithReminders() throws {
        let json = ##"{"id":"m1","name":"Sam","color":"#FF8FA3","avatar":"🐰","pointsToday":0,"pointsWeek":0,"balance":0,"transitionReminders":{"on":true,"minutes":[10],"repeat":{"every":5,"within":15},"leaveBy":true}}"##
        let m = try JSONDecoder().decode(Member.self, from: Data(json.utf8))
        #expect(m.transitionReminders?.repeat?.every == 5)
        let plain = try JSONDecoder().decode(Member.self, from: Data(##"{"id":"m1","name":"Sam","color":"#FF8FA3","avatar":null,"pointsToday":0,"pointsWeek":0,"balance":0,"transitionReminders":null}"##.utf8))
        #expect(plain.transitionReminders == nil)
    }
}


@Suite struct DemoFamilyTests {
    @Test func sampleDataDecodes() {
        #expect(DemoFamily.members.map(\.name) == ["Alex", "Sam", "Maya", "Leo"])
        #expect(DemoFamily.lists.map(\.name) == ["Groceries", "Weekend To-Dos"])
        #expect(DemoFamily.groceries.suggestions?.stores == ["Neighborhood market", "Warehouse club"])
        #expect(DemoFamily.chores.filter { !$0.completed }.count == 4)
        let doses = DemoFamily.dueDoses()
        #expect(doses.doses.count == 2 && !doses.names && doses.doses.allSatisfy { $0.name == nil })
        #expect(TodaySummary(board: DemoFamily.board()).choresLeft == 4)
        #expect(DemoFamily.tempCheck().step == .sleep)
        #expect(DemoFamily.battery().summary?.line == "62% · Good by this evening")
    }
}

@Suite struct GroceriesPickTests {
    private func lists(_ json: String) throws -> [FamilyList] { try JSONDecoder().decode([FamilyList].self, from: Data(json.utf8)) }

    @Test func prefersTheGroceriesType() throws {
        let typed = try lists(#"[{"id":"g","name":"Groceries","kind":"shopping","catalog":"shopping","archived":false,"itemCount":0,"openCount":0},{"id":"f","name":"Food","kind":"shopping","catalog":"groceries","archived":false,"itemCount":0,"openCount":0}]"#)
        #expect(FamilyList.groceries(in: typed)?.id == "f")
    }
    @Test func prefersTheDefaultGroceriesList() throws {
        let typed = try lists(#"[{"id":"f","name":"Food","kind":"shopping","catalog":"groceries","archived":false,"itemCount":0,"openCount":0},{"id":"c","name":"Costco","kind":"shopping","catalog":"groceries","isDefault":true,"archived":false,"itemCount":0,"openCount":0},{"id":"h","name":"Hardware","kind":"shopping","catalog":"shopping","isDefault":true,"archived":false,"itemCount":0,"openCount":0}]"#)
        #expect(FamilyList.groceries(in: typed)?.id == "c")
        #expect(FamilyList.groceries(in: [typed[0], typed[2]])?.id == "f")
    }
    @Test func olderServersFallBackToTheNameThenAnyShoppingList() throws {
        let old = try lists(#"[{"id":"c","name":"Costco","kind":"shopping","archived":false,"itemCount":0,"openCount":0},{"id":"g","name":"groceries","kind":"shopping","archived":false,"itemCount":0,"openCount":0}]"#)
        #expect(old[0].catalog == nil)
        #expect(FamilyList.groceries(in: old)?.id == "g")
        #expect(FamilyList.groceries(in: [old[0]])?.id == "c")
    }
}
