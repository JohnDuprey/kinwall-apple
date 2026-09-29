import SwiftUI
import WidgetKit
import KinwallKit

// Watch complications (docs/WIDGETS-AND-WATCH.md): Next event with the leave-by countdown,
// Chores left as a gauge, and Take now (how many medicines are due). They read the Board with the Watch's key, which the Watch app keeps in
// the shared Keychain group (SharedKeychain.widgetStore).

@main
struct KinwallComplications: WidgetBundle {
    var body: some Widget {
        NextEventComplication()
        ChoresLeftComplication()
        MedsDueComplication()
    }
}

struct BoardEntry: TimelineEntry {
    let date: Date
    let board: Board?
    var next: BoardEvent? {
        guard let board else { return nil }
        let (now, next) = board.nowAndNext(at: date)
        return next ?? now
    }
    var choresLeft: (remaining: Int, total: Int) {
        (board?.chores.reduce(0) { $0 + $1.remaining } ?? 0, board?.chores.reduce(0) { $0 + $1.total } ?? 0)
    }
}

struct BoardProvider: TimelineProvider {
    func placeholder(in context: Context) -> BoardEntry { BoardEntry(date: .now, board: nil) }

    func getSnapshot(in context: Context, completion: @escaping (BoardEntry) -> Void) {
        nonisolated(unsafe) let completion = completion // WidgetKit's callbacks may be called from any thread
        Task { completion(await load().first ?? BoardEntry(date: .now, board: nil)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BoardEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task { completion(Timeline(entries: await load(), policy: .after(.now.addingTimeInterval(30 * 60)))) }
    }

    /// One fetch, then an entry whenever an event today starts or ends, so "next" rolls over on time.
    private func load() async -> [BoardEntry] {
        guard let connection = try? SharedKeychain.widgetStore.load(),
              let board = try? await KinwallClient(connection).board(days: 1) else { return [BoardEntry(date: .now, board: nil)] }
        let now = Date.now
        let changes = board.events.filter { !$0.allDay }.flatMap { [$0.startDate, $0.endDate] }.compactMap { $0 }
            .filter { $0 > now && $0 < now.addingTimeInterval(30 * 60) }
        return ([now] + Set(changes).sorted()).map { BoardEntry(date: $0, board: board) }
    }
}

// MARK: - Next event

struct NextEventComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextEvent", provider: BoardProvider()) { entry in
            NextEventView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next event")
        .description("What's next, and when to leave.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct NextEventView: View {
    let entry: BoardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let e = entry.next
        switch family {
        case .accessoryInline:
            Text(e.map { "\($0.title) · \(time($0))" } ?? "Nothing more today")
        case .accessoryCorner:
            Image(systemName: "calendar")
                .widgetLabel { Text(e.map { "\($0.title) \(time($0))" } ?? "Free") }
        default:
            VStack(alignment: .leading, spacing: 1) {
                if let e {
                    Text(e.title).font(.headline).widgetAccentable().lineLimit(1)
                    Text(time(e)).font(.caption)
                    if let leave = e.leaveDate, leave > entry.date {
                        Text("🚗 leave in \(leave, style: .timer)").font(.caption).monospacedDigit()
                    }
                } else {
                    Text("Nothing more today").font(.headline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func time(_ e: BoardEvent) -> String {
        guard let start = e.startDate else { return "All day" }
        return start.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Chores left

struct ChoresLeftComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ChoresLeft", provider: BoardProvider()) { entry in
            let c = entry.choresLeft
            Gauge(value: Double(c.total - c.remaining), in: 0...Double(max(c.total, 1))) {
                Image(systemName: "checkmark")
            } currentValueLabel: {
                Text(c.total == 0 ? "–" : "\(c.remaining)")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Chores left")
        .description("A ring that fills as the family's chores get done.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - Meds due

/// How many doses are due now, never which medicines: a watch face is on show.
struct MedsEntry: TimelineEntry { let date: Date; let count: Int? }

struct MedsProvider: TimelineProvider {
    func placeholder(in context: Context) -> MedsEntry { MedsEntry(date: .now, count: 1) }
    func getSnapshot(in context: Context, completion: @escaping (MedsEntry) -> Void) { completion(placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MedsEntry>) -> Void) {
        nonisolated(unsafe) let completion = completion
        Task {
            var count: Int?
            if let connection = try? SharedKeychain.widgetStore.load() { count = (try? await KinwallClient(connection).dueDoses())?.doses.count ?? 0 }
            completion(Timeline(entries: [MedsEntry(date: .now, count: count)], policy: .after(.now.addingTimeInterval(15 * 60))))
        }
    }
}

struct MedsDueComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MedsDue", provider: MedsProvider()) { entry in
            MedsDueView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Take now")
        .description("How many medicines are due. Names stay off the watch face.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryCorner])
    }
}

struct MedsDueView: View {
    let entry: MedsEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        let n = entry.count ?? 0
        switch family {
        case .accessoryInline: Text(n == 0 ? "💊 Nothing due" : "💊 \(n) due")
        case .accessoryCorner: Image(systemName: "pills.fill").widgetLabel { Text(n == 0 ? "None due" : "\(n) due") }
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "pills.fill").font(.caption)
                    Text(entry.count == nil ? "–" : "\(n)").font(.title3.weight(.bold)).widgetAccentable()
                }
            }
        }
    }
}
