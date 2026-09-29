import SwiftUI
import WidgetKit
import KinwallKit

// First-pass widgets (docs/WIDGETS-AND-WATCH.md): Now & Next, Today, and a Chores-left ring.
// They read the Board with the widgets' own everyday-access key (SharedKeychain.widgetStore).

@main
struct KinwallWidgets: WidgetBundle {
    var body: some Widget {
        NowNextWidget()
        TodayWidget()
        ChoresLeftWidget()
        ChoresWidget()
        ListWidget()
        KinwallLiveActivity()
    }
}

// MARK: - Data

struct BoardEntry: TimelineEntry {
    let date: Date
    let board: Board?
    let problem: Problem?
    /// The demo family's sample data (Demo), marked with DemoBadge.
    var demo = false
    enum Problem { case signedOut, offline }

    var nowNext: (now: BoardEvent?, next: BoardEvent?) { board?.nowAndNext(at: date) ?? (nil, nil) }
    var todayEvents: [BoardEvent] {
        guard let board else { return [] }
        return board.events.filter { $0.date == board.today && ($0.allDay || ($0.endDate ?? .distantFuture) > date) }
    }
    var choresLeft: (remaining: Int, total: Int) {
        (board?.chores.reduce(0) { $0 + $1.remaining } ?? 0, board?.chores.reduce(0) { $0 + $1.total } ?? 0)
    }
}

struct BoardProvider: TimelineProvider {
    func placeholder(in context: Context) -> BoardEntry { BoardEntry(date: .now, board: Sample.board, problem: nil) }

    func getSnapshot(in context: Context, completion: @escaping (BoardEntry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        let fallback = placeholder(in: context)
        nonisolated(unsafe) let completion = completion // WidgetKit's callbacks may be called from any thread
        Task { completion(await load().first ?? fallback) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BoardEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion // WidgetKit's callbacks may be called from any thread
        Task {
            let entries = await load()
            // Fetch again in 30 minutes; the entries in between roll Now & Next over on their own.
            completion(Timeline(entries: entries, policy: .after(.now.addingTimeInterval(30 * 60))))
        }
    }

    /// One fetch, then an entry at every moment today's picture changes (an event starting or
    /// ending), so Now & Next stays right between fetches without touching the network.
    private func load() async -> [BoardEntry] {
        let board: Board
        var demo = false
        if let connection = try? SharedKeychain.widgetStore.load() {
            guard let fetched = try? await KinwallClient(connection).board(days: 7) else { return [BoardEntry(date: .now, board: nil, problem: .offline)] }
            board = fetched
        } else if Demo.isOn {
            board = Sample.board; demo = true
        } else {
            return [BoardEntry(date: .now, board: nil, problem: .signedOut)]
        }
        let now = Date.now
        let changes = board.events.filter { !$0.allDay && $0.date == board.today }
            .flatMap { [$0.startDate, $0.endDate] }.compactMap { $0 }
            .filter { $0 > now && $0 < now.addingTimeInterval(30 * 60) }
        return ([now] + Set(changes).sorted()).map { BoardEntry(date: $0, board: board, problem: nil, demo: demo) }
    }
}

// MARK: - Look

enum Palette {
    static let accent = Color(red: 0xA5 / 255, green: 0x61 / 255, blue: 0x3F / 255) // Peach's accent, deepened for text
    static func member(_ hex: String?) -> Color {
        guard let hex, hex.count == 7, let v = Int(hex.dropFirst(), radix: 16) else { return .secondary }
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

extension BoardEvent {
    var timeText: String {
        guard let start = startDate else { return "All day" }
        return start.formatted(date: .omitted, time: .shortened)
    }
}

struct ProblemView: View {
    let problem: BoardEntry.Problem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: problem == .signedOut ? "person.crop.circle.badge.questionmark" : "wifi.slash").foregroundStyle(.secondary)
            Text(problem == .signedOut ? "Open Kinwall to sign in" : "Can't reach Kinwall right now")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Now & Next

struct NowNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NowNext", provider: BoardProvider()) { entry in
            NowNextView(entry: entry).modifier(DemoBadge(on: entry.demo)).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Now & Next")
        .description("What's on now, what's next, and when to leave.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct NowNextView: View {
    let entry: BoardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let (now, next) = entry.nowNext
        switch family {
        case .accessoryInline:
            if let next { Text("\(next.title) · \(next.timeText)") } else { Text("Nothing more today") }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                if let next {
                    Text(next.title).font(.headline).widgetAccentable().lineLimit(1)
                    Text(next.timeText).font(.caption)
                    if let leave = next.leaveDate, leave > entry.date { Text("🚗 leave in \(leave, style: .timer)").font(.caption).monospacedDigit() }
                } else {
                    Text("Nothing more today").font(.headline)
                }
            }
        default:
            if let problem = entry.problem { ProblemView(problem: problem) } else {
                VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
                    if let now { row(label: "NOW", event: now, strong: true) }
                    if let next { row(label: "NEXT", event: next, strong: now == nil) }
                    if now == nil && next == nil {
                        Text("Nothing more today").font(.headline)
                        Text("Enjoy the evening.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row(label: String, event: BoardEvent, strong: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2.weight(.heavy)).foregroundStyle(Palette.accent)
            Text(event.title).font(strong ? .headline : .subheadline.weight(.semibold)).lineLimit(2)
            if label == "NOW", let end = event.endDate {
                Text("ends in \(end, style: .timer)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
            } else if let leave = event.leaveDate, leave > entry.date {
                Text("🚗 leave in \(leave, style: .timer)").font(.caption.weight(.semibold)).monospacedDigit()
            } else {
                Text(event.timeText).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Today

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Today", provider: BoardProvider()) { entry in
            TodayView(entry: entry).modifier(DemoBadge(on: entry.demo)).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("Today's plans and how many chores are left.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TodayView: View {
    let entry: BoardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let problem = entry.problem { ProblemView(problem: problem) } else {
            let events = entry.todayEvents.prefix(family == .systemLarge ? 7 : 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("TODAY").font(.caption.weight(.heavy)).foregroundStyle(Palette.accent)
                    Spacer()
                    let chores = entry.choresLeft
                    if chores.total > 0 {
                        Text(chores.remaining == 0 ? "Chores done 🎉" : "\(chores.remaining) chores left")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
                if events.isEmpty {
                    Text("Nothing on the calendar today.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(events) { e in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(Palette.member(e.color)).frame(width: 4, height: 28)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(e.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(e.timeText).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if family == .systemLarge, let board = entry.board, !board.chores.isEmpty {
                    Divider().padding(.vertical, 2)
                    ForEach(board.chores, id: \.memberId) { c in
                        HStack(spacing: 8) {
                            Text(c.avatar ?? "🌟")
                            Text(c.name ?? "Anyone").font(.caption.weight(.semibold))
                            Spacer()
                            Text(c.remaining == 0 ? "done" : "\(c.remaining) left").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Chores left (Lock Screen)

struct ChoresLeftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ChoresLeft", provider: BoardProvider()) { entry in
            ChoresLeftView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Chores left")
        .description("A ring that fills as the family's chores get done.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct ChoresLeftView: View {
    let entry: BoardEntry
    var body: some View {
        let c = entry.choresLeft
        Gauge(value: Double(c.total - c.remaining), in: 0...Double(max(c.total, 1))) {
            Image(systemName: "checkmark")
        } currentValueLabel: {
            Text(c.total == 0 ? "–" : "\(c.remaining)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }
}

// MARK: - Sample data (widget gallery, and the demo family)

/// The demo family (src/demo.ts sets SharedKeychain.demoStore while the app shows it): the widgets
/// show Sample data for "Our Family" instead of calling a server. Never while a real family is connected.
enum Demo {
    static var isOn: Bool { (try? SharedKeychain.widgetStore.load()) == nil && (try? SharedKeychain.demoStore.load()) != nil }

    static let members: [Member] = decode("""
    [{"id":"m1","name":"Alex","color":"#7AB8FF","avatar":"🦊","pointsToday":10,"pointsWeek":40,"balance":12},
     {"id":"m2","name":"Sam","color":"#FF8FA3","avatar":"🐰","pointsToday":5,"pointsWeek":25,"balance":30},
     {"id":"m3","name":"Maya","color":"#7ED9A6","avatar":"🦄","pointsToday":5,"pointsWeek":15,"balance":42},
     {"id":"m4","name":"Leo","color":"#F5A65B","avatar":"🦖","pointsToday":0,"pointsWeek":20,"balance":18}]
    """)
    static let chores: [ChoreDay] = decode("""
    [{"id":"ch2","title":"Feed the dog","emoji":"🐕","memberId":"m3","points":5,"completed":true,"completedBy":"m3"},
     {"id":"ch7","title":"Practice piano","emoji":"🎹","memberId":"m3","points":10,"completed":false},
     {"id":"ch6","title":"Tidy toys","emoji":"🧸","memberId":"m4","points":5,"completed":false},
     {"id":"ch8","title":"Take out the recycling","emoji":"♻️","memberId":"m4","points":5,"completed":false},
     {"id":"ch4","title":"Water plants","emoji":"🪴","points":5,"completed":false}]
    """)
    static let groceries: ListDetail = decode("""
    {"list":{"id":"l1","name":"Groceries","emoji":"🛒","kind":"shopping","archived":false,"itemCount":6,"openCount":5},
     "items":[{"id":"li1","listId":"l1","title":"Milk","quantity":"1 gal","done":false},
              {"id":"li2","listId":"l1","title":"Eggs","quantity":"1 dozen","done":false},
              {"id":"li4","listId":"l1","title":"Apples","quantity":"6","done":false},
              {"id":"li5","listId":"l1","title":"Paper towels","done":false},
              {"id":"g1","listId":"l1","title":"Blueberries","quantity":"3 pints","done":false},
              {"id":"li3","listId":"l1","title":"Bread","done":true}]}
    """)
    private static func decode<T: Decodable>(_ json: String) -> T { try! JSONDecoder().decode(T.self, from: Data(json.utf8)) }
}

/// "Our Family · Demo" in the corner of Home Screen widgets showing the demo family.
struct DemoBadge: ViewModifier {
    let on: Bool
    @Environment(\.widgetFamily) private var family
    @ViewBuilder func body(content: Content) -> some View {
        if on, [.systemSmall, .systemMedium, .systemLarge].contains(family) {
            content.overlay(alignment: .bottomTrailing) {
                Text(family == .systemSmall ? "Demo" : "Our Family · Demo").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
        } else { content }
    }
}

enum Sample {
    static var board: Board {
        let iso = ISO8601DateFormatter()
        let now = Date.now
        let day = HouseholdDate.key(timezone: nil)
        func event(_ id: String, _ title: String, _ from: Double, _ to: Double, leave: Double? = nil, color: String) -> BoardEvent {
            BoardEvent(id: id, title: title, start: iso.string(from: now.addingTimeInterval(from * 60)), end: iso.string(from: now.addingTimeInterval(to * 60)),
                       allDay: false, memberIds: [], color: color, location: nil, leaveAt: leave.map { iso.string(from: now.addingTimeInterval($0 * 60)) }, date: day)
        }
        return Board(today: day,
                     events: [event("a", "Reading time", -20, 25, color: "#7ED9A6"), event("b", "Soccer Practice", 20, 110, leave: 5, color: "#FF8FA3"), event("c", "Piano Lesson", 70, 115, color: "#7ED9A6"), event("d", "Movie Night", 180, 300, color: "#B39DFF")],
                     items: [],
                     chores: [.init(memberId: "m3", name: "Maya", avatar: "🦄", color: "#7ED9A6", remaining: 1, total: 2), .init(memberId: "m4", name: "Leo", avatar: "🦖", color: "#F5A65B", remaining: 2, total: 2),
                              .init(memberId: nil, name: nil, avatar: nil, color: nil, remaining: 1, total: 1)])
    }
}
