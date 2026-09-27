import SwiftUI
import KinwallKit

// MARK: - Today

/// Now & Next with the live countdown, then the rest of today.
struct TodayView: View {
    let client: KinwallClient
    @State private var board: Board?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                if let board {
                    let (now, next) = board.nowAndNext(at: .now)
                    if let now { row("NOW", now) }
                    if let next { row("NEXT", next) }
                    if now == nil && next == nil { Text("Nothing more today").foregroundStyle(.secondary) }
                    let later = board.events.filter { $0.date == board.today && $0.id != now?.id && $0.id != next?.id && ($0.allDay || ($0.endDate ?? .distantFuture) > .now) }
                    if !later.isEmpty {
                        Section("Later today") {
                            ForEach(later) { e in
                                VStack(alignment: .leading) {
                                    Text(e.title).font(.headline).lineLimit(2)
                                    Text(e.allDay ? "All day" : (e.startDate ?? .now).formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } else if failed {
                    Text("Can't reach Kinwall right now").foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Today")
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func row(_ label: String, _ e: BoardEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.heavy)).foregroundStyle(.orange)
            Text(e.title).font(.headline).lineLimit(2)
            if label == "NOW", let end = e.endDate {
                Text("ends in \(end, style: .timer)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            } else if let leave = e.leaveDate, leave > .now {
                Text("🚗 leave in \(leave, style: .timer)").font(.caption.weight(.semibold)).monospacedDigit()
            } else {
                Text(e.allDay ? "All day" : (e.startDate ?? .now).formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func load() async {
        do { board = try await client.board(days: 1); failed = false } catch { failed = board == nil }
    }
}

// MARK: - My chores

/// This Watch's person's chores for today (plus Anyone chores, credited to them). Tap to tick off.
struct ChoresView: View {
    let client: KinwallClient
    @AppStorage("person") private var personId = "" // chosen on the Watch; "" = not chosen yet
    @State private var members: [Member] = []
    @State private var chores: [ChoreDay] = []
    @State private var day = ""
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                if members.isEmpty && !failed {
                    ProgressView()
                } else if failed {
                    Text("Can't reach Kinwall right now").foregroundStyle(.secondary)
                } else if personId.isEmpty || !members.contains(where: { $0.id == personId }) {
                    Section("Whose Watch is this?") {
                        ForEach(members) { m in
                            Button("\(m.avatar ?? "🙂") \(m.name)") { personId = m.id; Task { await load() } }
                        }
                    }
                } else {
                    let mine = chores.filter { $0.memberId == personId || $0.isAnyone }.sorted { !$0.completed && $1.completed }
                    if mine.isEmpty { Text("No chores today 🎉").foregroundStyle(.secondary) }
                    ForEach(mine) { chore in choreRow(chore) }
                    Section {
                        Button("Not you? Change person") { personId = "" }.font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(members.first { $0.id == personId }.map { "\($0.avatar ?? "") \($0.name)" } ?? "Chores")
        }
        .task { await load() }
    }

    @ViewBuilder private func choreRow(_ chore: ChoreDay) -> some View {
        let needsPhone = !chore.completed && (chore.checklist.map { !$0.isFinished } ?? false)
        Button {
            guard !needsPhone else { return }
            Task { await toggle(chore) }
        } label: {
            HStack {
                Image(systemName: chore.completed ? "checkmark.circle.fill" : "circle").foregroundStyle(chore.completed ? .green : .secondary)
                VStack(alignment: .leading) {
                    Text("\(chore.emoji ?? "⭐") \(chore.title)").lineLimit(2).strikethrough(chore.completed)
                    if needsPhone, let cl = chore.checklist {
                        Text("☑ \(cl.done)/\(cl.total) · finish on iPhone").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func toggle(_ chore: ChoreDay) async {
        WKHaptic.play(chore.completed ? .click : .success)
        do {
            if chore.completed { try await client.uncomplete(chore: chore.id, on: day) }
            else { try await client.complete(chore: chore.id, on: day, by: chore.memberId ?? personId) } // Anyone chores count for this Watch's person
        } catch { WKHaptic.play(.failure) }
        await load()
    }

    private func load() async {
        do {
            let tz = try? await client.settings().timezone
            day = HouseholdDate.key(timezone: tz)
            async let m = client.members()
            async let c = client.chores(on: day)
            (members, chores) = try await (m, c)
            failed = false
        } catch { failed = members.isEmpty }
    }
}

// MARK: - Lists

/// The family's lists; big rows to tick off while shopping, and dictation to add.
struct ListsView: View {
    let client: KinwallClient
    @State private var lists: [FamilyList] = []
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                if lists.isEmpty && !failed { ProgressView() }
                if failed { Text("Can't reach Kinwall right now").foregroundStyle(.secondary) }
                ForEach(lists) { l in
                    NavigationLink {
                        ListItemsView(client: client, list: l)
                    } label: {
                        HStack {
                            Text("\(l.emoji ?? "📝") \(l.name)").lineLimit(1)
                            Spacer()
                            Text("\(l.openCount)").foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Lists")
        }
        .task { await load() }
    }

    private func load() async {
        do { lists = try await client.lists().filter { !$0.archived }; failed = false } catch { failed = lists.isEmpty }
    }
}

struct ListItemsView: View {
    let client: KinwallClient
    let list: FamilyList
    @State private var items: [ListItem] = []
    @State private var newItem = ""

    var body: some View {
        List {
            TextField("Add an item", text: $newItem) // dictation or Scribble
                .onSubmit { Task { await add() } }
            ForEach(items.sorted { !$0.done && $1.done }) { item in
                Button {
                    Task { await toggle(item) }
                } label: {
                    HStack {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle").foregroundStyle(item.done ? .green : .secondary)
                        Text(item.quantity.map { "\(item.title) · \($0)" } ?? item.title).strikethrough(item.done).lineLimit(2)
                    }
                    .padding(.vertical, 4) // big targets for a quick tap in the store
                }
            }
        }
        .navigationTitle(list.name)
        .task { await load() }
    }

    private func toggle(_ item: ListItem) async {
        WKHaptic.play(.click)
        try? await client.setDone(!item.done, item: item.id, in: list.id)
        await load()
    }

    private func add() async {
        let title = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newItem = ""
        _ = try? await client.addItems([title], to: list.id)
        await load()
    }

    private func load() async { if let detail = try? await client.list(list.id) { items = detail.items } }
}

import WatchKit
private enum WKHaptic {
    static func play(_ type: WKHapticType) { WKInterfaceDevice.current().play(type) }
}
