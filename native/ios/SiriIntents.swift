import AppIntents
import KinwallKit

// Siri and Shortcuts (M5, docs/WIDGETS-AND-WATCH.md): Add to a list, What's next, Complete a chore.
// They run without opening the app, using the widgets' everyday-access key. Parameters are plain
// strings picked from live options (see WidgetIntents.swift for why custom entities are avoided).

private func client() throws -> KinwallClient {
    guard let connection = try SharedKeychain.widgetStore.load() else { throw KinwallIntentError.signedOut }
    return KinwallClient(connection)
}

enum KinwallIntentError: Error, CustomLocalizedStringResourceConvertible {
    case signedOut, noList(String), noChore(String)
    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .signedOut: "Open Kinwall and sign in first."
        case .noList(let name): "There's no list called \(name)."
        case .noChore(let name): "There's no chore called \(name) today."
        }
    }
}

struct ListNames: DynamicOptionsProvider {
    func results() async throws -> [String] { try await client().lists().filter { !$0.archived }.map(\.name) }
}

struct AddToListIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to a list"
    static let description = IntentDescription("Adds an item to a Kinwall list, like Groceries.")
    @Parameter(title: "Item", requestValueDialog: "What should I add?") var item: String
    @Parameter(title: "List", optionsProvider: ListNames()) var list: String?

    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$item) to \(\.$list)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let kinwall = try client()
        let lists = try await kinwall.lists().filter { !$0.archived }
        let target: FamilyList?
        if let list, !list.isEmpty {
            target = lists.first { $0.name.localizedCaseInsensitiveCompare(list) == .orderedSame }
                ?? lists.first { $0.name.localizedCaseInsensitiveContains(list) }
        } else {
            target = lists.first { $0.kind == .shopping } ?? lists.first // no list named: the shopping list
        }
        guard let target else { throw KinwallIntentError.noList(list ?? "Groceries") }
        _ = try await kinwall.addItems([item], to: target.id)
        return .result(dialog: "Added \(item) to \(target.name).")
    }
}

struct WhatsNextIntent: AppIntent {
    static let title: LocalizedStringResource = "What's next"
    static let description = IntentDescription("Tells you what's on now and what's next today.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let board = try await client().board(days: 1)
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

struct OpenChoreNames: DynamicOptionsProvider {
    func results() async throws -> [String] {
        let kinwall = try client()
        let day = HouseholdDate.key(timezone: try? await kinwall.settings().timezone)
        return try await kinwall.chores(on: day).filter { !$0.completed }.map(\.title)
    }
}

struct CompleteChoreIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete a chore"
    static let description = IntentDescription("Marks one of today's chores done.")
    @Parameter(title: "Chore", requestValueDialog: "Which chore?", optionsProvider: OpenChoreNames()) var chore: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let kinwall = try client()
        let day = HouseholdDate.key(timezone: try? await kinwall.settings().timezone)
        let open = try await kinwall.chores(on: day).filter { !$0.completed }
        guard let match = open.first(where: { $0.title.localizedCaseInsensitiveCompare(chore) == .orderedSame })
                ?? open.first(where: { $0.title.localizedCaseInsensitiveContains(chore) }) else { throw KinwallIntentError.noChore(chore) }
        if let checklist = match.checklist, !checklist.isFinished {
            return .result(dialog: "\(match.title) has a checklist to finish first. Open Kinwall to tick it off.")
        }
        // ponytail: an Anyone chore done by voice credits nobody in particular; asking who did it is a follow-up.
        try await kinwall.complete(chore: match.id, on: day)
        return .result(dialog: "Marked \(match.title) done. \(match.points) points!")
    }
}

struct KinwallShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddToListIntent(), phrases: ["Add to my \(.applicationName) list", "Add something to \(.applicationName)"],
                    shortTitle: "Add to a list", systemImageName: "cart.badge.plus")
        AppShortcut(intent: WhatsNextIntent(), phrases: ["What's next on \(.applicationName)", "What's next in \(.applicationName)"],
                    shortTitle: "What's next", systemImageName: "calendar")
        AppShortcut(intent: CompleteChoreIntent(), phrases: ["Complete a chore in \(.applicationName)", "Mark a \(.applicationName) chore done"],
                    shortTitle: "Complete a chore", systemImageName: "checkmark.circle")
    }
}
