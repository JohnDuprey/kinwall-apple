import AppIntents
import KinwallKit
import SwiftUI
import WidgetKit

// Siri, Shortcuts and Spotlight's App Shortcuts (docs/WIDGETS-AND-WATCH.md): add to a list, what's
// on today, what's next, start shopping, mark a chore done, and the night screen. They run in the
// app's own process without opening it (the last two and Start shopping open it), with the widgets'
// everyday-access key from the shared Keychain group, so the server's rules for that key apply: it
// can add to lists and tick chores, and a device that belongs to one person can only tick theirs.
//
// Lists, people, today's chores and stores are entities, so Siri can match them in a phrase
// ("Add to Groceries in Kinwall"); each also answers to its plain name, without the emoji.
// App-only: the widget extension's settings keep plain strings (WidgetIntents.swift), and
// OpenIntents.swift holds the intents both share.

func intentClient() throws -> KinwallClient {
    guard let connection = try SharedKeychain.widgetStore.load() else { throw KinwallIntentError.signedOut }
    return KinwallClient(connection)
}

/// The family to ask: nil while the app shows the demo (KinwallKit DemoFamily, where nothing is
/// saved); signed out, the intent says to sign in.
func family() throws -> KinwallClient? { DemoFamily.isOn ? nil : try intentClient() }
private let demoNote = " This is the demo, so nothing is saved."

enum KinwallIntentError: Error, CustomLocalizedStringResourceConvertible {
    case signedOut, noList, noShoppingList, checklist(String), server(String)
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .signedOut: "Open Kinwall and sign in first."
        case .noList: "Kinwall has no list to add to yet."
        case .noShoppingList: "Kinwall has no shopping list yet."
        case .checklist(let title): "\(title) has a checklist to finish first. Open Kinwall to tick it off."
        case .server(let message): "Kinwall said: \(message)"
        }
    }
}

/// The server's refusal in its own words (a device that belongs to someone else, a 409 checklist).
private func explained<T>(_ work: () async throws -> T) async throws -> T {
    do { return try await work() } catch let e as APIError where e != .unreachable { throw KinwallIntentError.server(e.message) }
}

/// The household's day, for chores.
private func today(_ kinwall: KinwallClient) async -> String {
    HouseholdDate.key(timezone: try? await kinwall.settings().timezone)
}

/// Groceries (FamilyList.groceries), else the first list.
private func defaultList(_ lists: [FamilyList], shopping: Bool = false) -> FamilyList? {
    FamilyList.groceries(in: lists) ?? (shopping ? nil : lists.first { !$0.archived })
}

// MARK: - Entities

struct ListEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "List"
    static let defaultQuery = ListQuery()
    let id: String
    let name: String
    let emoji: String?
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(emoji.map { "\($0) " } ?? "")\(name)", synonyms: ["\(name)"]) }
    init(_ l: FamilyList) { id = l.id; name = l.name; emoji = l.emoji }
}

struct ListQuery: EntityStringQuery {
    func all() async throws -> [ListEntity] { try await (family()?.lists() ?? DemoFamily.lists).filter { !$0.archived }.map(ListEntity.init) }
    func entities(for identifiers: [String]) async throws -> [ListEntity] { try await all().filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [ListEntity] { try await all().filter { $0.name.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [ListEntity] { try await all() }
    func defaultResult() async -> ListEntity? { (try? await family()?.lists() ?? DemoFamily.lists).flatMap { defaultList($0) }.map(ListEntity.init) }
}

struct PersonEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Person"
    static let defaultQuery = PersonQuery()
    let id: String
    let name: String
    let avatar: String?
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(avatar.map { "\($0) " } ?? "")\(name)", synonyms: ["\(name)"]) }
    init(_ m: Member) { id = m.id; name = m.name; avatar = m.avatar }
}

struct PersonQuery: EntityStringQuery {
    func all() async throws -> [PersonEntity] { try await (family()?.members() ?? DemoFamily.members).map(PersonEntity.init) }
    func entities(for identifiers: [String]) async throws -> [PersonEntity] { try await all().filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [PersonEntity] { try await all().filter { $0.name.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [PersonEntity] { try await all() }
}

/// One of today's chores, not done yet.
struct ChoreEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Chore"
    static let defaultQuery = ChoreQuery()
    let id: String
    let title: String
    let emoji: String?
    let memberId: String?
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(emoji.map { "\($0) " } ?? "")\(title)", synonyms: ["\(title)"]) }
    init(_ c: ChoreDay) { id = c.id; title = c.title; emoji = c.emoji; memberId = c.memberId }
}

struct ChoreQuery: EntityStringQuery {
    func all() async throws -> [ChoreEntity] {
        guard let kinwall = try family() else { return DemoFamily.chores.filter { !$0.completed }.map(ChoreEntity.init) }
        return try await kinwall.chores(on: today(kinwall)).filter { !$0.completed }.map(ChoreEntity.init)
    }
    func entities(for identifiers: [String]) async throws -> [ChoreEntity] { try await all().filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [ChoreEntity] { try await all().filter { $0.title.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [ChoreEntity] { try await all() }
}

/// A store the family shops at (the shopping lists' stores).
struct StoreEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Store"
    static let defaultQuery = StoreQuery()
    let id: String // the store's name
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }
}

struct StoreQuery: EntityStringQuery {
    func all() async throws -> [StoreEntity] {
        guard let kinwall = try family() else { return (DemoFamily.groceries.suggestions?.stores ?? []).map(StoreEntity.init) }
        guard let list = defaultList(try await kinwall.lists(), shopping: true) else { return [] }
        return (try await kinwall.list(list.id).suggestions?.stores ?? []).map(StoreEntity.init)
    }
    func entities(for identifiers: [String]) async throws -> [StoreEntity] { identifiers.map(StoreEntity.init) }
    func entities(matching string: String) async throws -> [StoreEntity] { try await all().filter { $0.id.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [StoreEntity] { try await all() }
}

// MARK: - Intents

struct AddToListIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to a list"
    static let description = IntentDescription("Adds an item to a Kinwall list. Groceries unless you say another list.")
    @Parameter(title: "Item", requestValueDialog: "What should I add?") var item: String
    @Parameter(title: "List") var list: ListEntity?

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$item) to \(\.$list)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let kinwall = try family()
        let target: ListEntity
        if let list { target = list } else {
            guard let fallback = defaultList(try await kinwall?.lists() ?? DemoFamily.lists) else { throw KinwallIntentError.noList }
            target = ListEntity(fallback)
        }
        guard let kinwall else { return .result(dialog: "Added \(item) to \(target.name).\(demoNote)") }
        try await explained { _ = try await kinwall.addItems([item], to: target.id) }
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "Added \(item) to \(target.name).")
    }
}

struct WhatsOnTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "What's on today"
    static let description = IntentDescription("Today's events that are still ahead, and how many chores are left.")

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let board = try await explained { try await family()?.board(days: 1) } ?? DemoFamily.board()
        let summary = TodaySummary(board: board)
        return .result(dialog: IntentDialog(stringLiteral: summary.spoken), view: TodaySnippet(summary: summary))
    }
}

/// What Siri and Shortcuts show under "What's on today".
struct TodaySnippet: View {
    let summary: TodaySummary
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(summary.events.prefix(6)) { e in
                HStack(alignment: .firstTextBaseline) {
                    Text(e.startDate?.formatted(date: .omitted, time: .shortened) ?? "All day").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
                    Text(e.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
            }
            if summary.events.isEmpty { Text("Nothing else on the calendar today.").font(.subheadline).foregroundStyle(.secondary) }
            if summary.choresTotal > 0 {
                Label(summary.choresLeft == 0 ? "All chores done" : "\(summary.choresLeft) of \(summary.choresTotal) chores left", systemImage: "checkmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

struct WhatsNextIntent: AppIntent {
    static let title: LocalizedStringResource = "What's next"
    static let description = IntentDescription("Tells you what's on now and what's next today.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let board = try await explained { try await family()?.board(days: 1) } ?? DemoFamily.board()
        let (now, next) = board.nowAndNext(at: .now)
        func time(_ e: BoardEvent) -> String { e.startDate?.formatted(date: .omitted, time: .shortened) ?? "all day" }
        var parts: [String] = []
        if let now { parts.append("Now: \(now.title).") }
        if let next {
            var line = "Next: \(next.title) at \(time(next))."
            if let leave = next.leaveDate, leave > .now { line += " Leave by \(leave.formatted(date: .omitted, time: .shortened))." }
            parts.append(line)
        }
        return .result(dialog: IntentDialog(stringLiteral: parts.isEmpty ? "Nothing more on the calendar today." : parts.joined(separator: " ")))
    }
}

struct CompleteChoreIntent: AppIntent {
    static let title: LocalizedStringResource = "Mark a chore done"
    static let description = IntentDescription("Marks one of today's chores done. For an Anyone chore, say who did it and they get the points.")
    @Parameter(title: "Chore", requestValueDialog: "Which chore?") var chore: ChoreEntity
    @Parameter(title: "Who did it") var person: PersonEntity?

    static var parameterSummary: some ParameterSummary { Summary("Mark \(\.$chore) done for \(\.$person)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let kinwall = try family() else { return .result(dialog: "Marked \(chore.title) done.\(demoNote)") }
        let day = await today(kinwall)
        let current = try await explained { try await kinwall.chores(on: day) }.first { $0.id == chore.id }
        if let checklist = current?.checklist, !checklist.isFinished { throw KinwallIntentError.checklist(chore.title) }
        if current?.completed == true { return .result(dialog: "\(chore.title) is already done.") }
        // A person's own chore counts for them; an Anyone chore for whoever was named (or nobody in particular).
        try await explained { try await kinwall.complete(chore: chore.id, on: day, by: chore.memberId ?? person?.id) }
        WidgetCenter.shared.reloadAllTimelines()
        let points = current.map { " \($0.points) points!" } ?? ""
        return .result(dialog: "Marked \(chore.title) done.\(points)")
    }
}

/// Opens shopping mode on Groceries (or the first shopping list), at the store if one's named.
struct StartShoppingIntent: AppIntent {
    static let title: LocalizedStringResource = "Start shopping"
    static let description = IntentDescription("Opens Kinwall's shopping mode on Groceries, optionally at a store.")
    static let openAppWhenRun = true
    @Parameter(title: "Store") var store: StoreEntity?

    static var parameterSummary: some ParameterSummary { Summary("Start shopping at \(\.$store)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let list = defaultList(try await family()?.lists() ?? DemoFamily.lists, shopping: true) else { throw KinwallIntentError.noShoppingList }
        AppLink.open(AppLink.shop(list: list.id, store: store?.id))
        return .result()
    }
}

// MARK: - App Shortcuts

struct KinwallShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddToListIntent(), phrases: [
            "Add to \(\.$list) in \(.applicationName)",
            "Add something to \(\.$list) in \(.applicationName)",
            "Add to my \(.applicationName) list",
            "Add something to \(.applicationName)",
        ], shortTitle: "Add to a list", systemImageName: "cart.badge.plus")
        AppShortcut(intent: WhatsOnTodayIntent(), phrases: [
            "What's on today in \(.applicationName)",
            "What's on \(.applicationName) today",
            "What's happening today in \(.applicationName)",
        ], shortTitle: "What's on today", systemImageName: "calendar")
        AppShortcut(intent: WhatsNextIntent(), phrases: ["What's next on \(.applicationName)", "What's next in \(.applicationName)"],
                    shortTitle: "What's next", systemImageName: "clock")
        AppShortcut(intent: StartShoppingIntent(), phrases: [
            "Start shopping in \(.applicationName)",
            "Start shopping at \(\.$store) in \(.applicationName)",
            "Go shopping with \(.applicationName)",
        ], shortTitle: "Start shopping", systemImageName: "cart")
        AppShortcut(intent: CompleteChoreIntent(), phrases: [
            "Mark \(\.$chore) done in \(.applicationName)",
            "Mark a chore done in \(.applicationName)",
            "Complete a chore in \(.applicationName)",
        ], shortTitle: "Mark a chore done", systemImageName: "checkmark.circle")
        AppShortcut(intent: NightScreenIntent(), phrases: [
            "Start the night screen in \(.applicationName)",
            "Start \(.applicationName) night screen",
            "\(.applicationName) goodnight",
        ], shortTitle: "Night screen", systemImageName: "moon.stars")
    }
}
