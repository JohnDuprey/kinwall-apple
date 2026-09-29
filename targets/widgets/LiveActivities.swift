import ActivityKit
import AppIntents
import KinwallKit
import SwiftUI
import WidgetKit

// The Live Activities (modules/kinwall-native/ios/LiveActivities.swift starts them; the web app
// decides what they say): a cooking timer, a shopping trip, the next leave-by or start-prep
// time, and a medicine that's due, on the Lock Screen and in the Dynamic Island. Countdowns tick on their own
// (Text(timerInterval:)); when a timer or leave-by time passes, the activity goes stale and says
// "Done" or "Leave now" without an update.

struct KinwallLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KinwallActivityAttributes.self) { context in
            LockScreenActivity(context: context)
                .activityBackgroundTint(context.theme.bg)
                .activitySystemActionForegroundColor(context.theme.fg)
                .widgetURL(context.attributes.link)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Text(context.attributes.icon)
                        Text(context.attributes.name).lineLimit(1)
                    }
                    .font(.subheadline.weight(.semibold)).padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Trailing(context: context).font(.title3.weight(.semibold)).lineLimit(1).frame(maxWidth: 96, alignment: .trailing)
                        .foregroundStyle(context.theme.accentOnDark).padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.headline).font(.headline).lineLimit(2)
                        if context.attributes.kind == "shopping" { ShoppingLineView(context: context).font(.subheadline).foregroundStyle(.secondary) }
                        else if let line = context.islandLine { Text(line).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                        if context.attributes.kind == "shopping" { ShoppingButtons(context: context, onDark: true) }
                        if context.attributes.kind == "medication" { Text(context.medicationLine).font(.subheadline).foregroundStyle(.secondary).lineLimit(1); DoseButtons(context: context, onDark: true) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
                }
            } compactLeading: {
                Text(context.attributes.icon)
            } compactTrailing: {
                Trailing(context: context).frame(maxWidth: 52).foregroundStyle(context.theme.accentOnDark)
            } minimal: {
                Text(context.attributes.icon)
            }
            .widgetURL(context.attributes.link)
            .keylineTint(context.theme.accentOnDark)
        }
    }
}

// MARK: - Words

extension KinwallActivityAttributes {
    var icon: String { ["cooking": "⏲️", "shopping": "🛒", "leave": "🚗", "prep": "🍳", "medication": "💊"][kind] ?? "📅" }
    /// Open: shopping mode for a trip, the calendar for a leave-by; the app as it was for cooking.
    var link: URL? {
        switch kind {
        case "shopping": listId.flatMap { URL(string: "family.kinwall.app:/open?to=lists/\($0)/shop") }
        case "leave", "prep", "medication": URL(string: "family.kinwall.app:/open?to=calendar")
        default: nil
        }
    }
}

extension ActivityViewContext<KinwallActivityAttributes> {
    var s: KinwallActivityAttributes.ContentState { state }
    /// Past its time: a timer that's up, a leave-by or start-prep time that has come.
    var due: Bool { isStale || s.done || (s.date.map { $0 <= .now } ?? false) }

    var headline: String {
        switch attributes.kind {
        case "cooking": due ? "Done: \(s.title)" : s.title
        case "shopping": s.count == 0 ? "All done at \(attributes.name)" : s.title.isEmpty ? "\(s.count) left" : s.title
        case "medication": s.title // the web app's headline ("Time for Maya's medicine")
        default: due ? (s.detail ?? "Time to go") : s.title
        }
    }

    var subline: String {
        switch attributes.kind {
        case "cooking": [s.detail, s.count > 0 ? "+\(s.count) more" : nil, attributes.name].compactMap { $0 }.joined(separator: " · ") // the step first; the recipe fits if it can
        default: attributes.name
        }
    }

    /// The expanded island's second line for a cooking timer (its leading region already names the recipe).
    var islandLine: String? {
        attributes.kind == "cooking" ? [s.detail, s.count > 0 ? "+\(s.count) more" : nil].compactMap { $0 }.joined(separator: " · ") : nil
    }

    /// Shopping: where the current item is, then what's after it (KinwallKit ShoppingLine). `detail`
    /// is the current item's aisle; the queue carries it first, then up to four after it.
    var shoppingLine: ShoppingLine {
        let after = (s.queue ?? []).drop { $0.id != s.itemId }.dropFirst().first
        return ShoppingLine(aisle: s.detail, next: after.map { ($0.title, $0.aisle) }, left: s.count)
    }

    var theme: ActivityTheme { ActivityTheme(attributes.colors) }

    /// Kind words only, never "missed": "Due now · still time until 8:00 PM", "Still time · until 8:00 PM".
    var medicationLine: String {
        let until = (attributes.endsAt ?? s.date).map { $0.formatted(date: .omitted, time: .shortened) } ?? ""
        return s.detail == "late" ? "Still time · until \(until)" : "Due now · still time until \(until)"
    }
}

/// The countdown, or what the activity counts.
struct Trailing: View {
    let context: ActivityViewContext<KinwallActivityAttributes>
    var body: some View {
        if context.attributes.kind == "shopping" {
            Text("\(context.s.count) left").monospacedDigit()
        } else if let date = context.s.date, !context.due {
            Text(timerInterval: Date.now...max(date, .now), countsDown: true).monospacedDigit().multilineTextAlignment(.trailing)
        } else {
            Text(context.attributes.kind == "cooking" ? "Done" : "Now")
        }
    }
}

// MARK: - Lock Screen

struct LockScreenActivity: View {
    let context: ActivityViewContext<KinwallActivityAttributes>
    var body: some View {
        let theme = context.theme
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(context.attributes.icon).font(.title3)
                Text(lead).font(.subheadline.weight(.semibold)).foregroundStyle(theme.fg.opacity(0.75)).lineLimit(1)
                Spacer(minLength: 8)
                Trailing(context: context).font(.title2.weight(.semibold)).foregroundStyle(theme.accent).lineLimit(1).frame(maxWidth: 110, alignment: .trailing)
            }
            Text(context.headline).font(.headline).foregroundStyle(context.due ? theme.accent : theme.fg).lineLimit(2)
            if context.attributes.kind == "shopping" {
                ShoppingLineView(context: context).font(.subheadline).foregroundStyle(theme.fg.opacity(0.75))
                ShoppingButtons(context: context)
            }
            if context.attributes.kind == "medication" {
                Text(context.medicationLine).font(.subheadline).foregroundStyle(theme.fg.opacity(0.75)).lineLimit(1)
                DoseButtons(context: context)
            }
        }
        .padding(16)
    }

    /// Leave / prep: "Soccer practice · leave in" before the countdown; the others: their subline.
    private var lead: String {
        switch context.attributes.kind {
        case "leave": context.due ? context.attributes.name : "\(context.attributes.name) · leave in"
        case "prep": context.due ? context.attributes.name : "\(context.attributes.name) · start prep in"
        // The count is on the right; where things are goes under the item (ShoppingLineView).
        case "shopping": context.attributes.name
        case "medication": context.attributes.name // the web app's label, generic unless the device opted into names
        default: context.subline
        }
    }
}

/// "Dairy · then Dishwasher tablets (Aisle 17)": only the next item's name gives way when it's long,
/// never where things are. Nothing once the trip is done.
struct ShoppingLineView: View {
    let context: ActivityViewContext<KinwallActivityAttributes>
    var body: some View {
        let line = context.shoppingLine
        if context.s.count > 0, !line.text.isEmpty {
            HStack(spacing: 0) {
                Text(line.lead).layoutPriority(2)
                if !line.name.isEmpty { Text(line.name).truncationMode(.tail) }
                if !line.tail.isEmpty { Text(line.tail).layoutPriority(2) }
            }
            .lineLimit(1)
        }
    }
}

/// Taken and Snooze 10 min (MarkDoseActivityIntent, native/ios/LiveActivityIntents.swift).
struct DoseButtons: View {
    let context: ActivityViewContext<KinwallActivityAttributes>
    var onDark = false
    var body: some View {
        if let dose = context.attributes.dose {
            HStack(spacing: 10) {
                Button(intent: MarkDoseActivityIntent(medicationId: dose.medicationId, date: dose.date, time: dose.time, action: "taken")) {
                    Label("Taken", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .tint(context.theme.accent)
                Button(intent: MarkDoseActivityIntent(medicationId: dose.medicationId, date: dose.date, time: dose.time, action: "snooze")) {
                    Label("Snooze 10 min", systemImage: "zzz").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(onDark ? .white : context.theme.fg)
            }
            .font(.subheadline.weight(.semibold))
        }
    }
}

/// Got it ticks the next item (GotItIntent, native/ios/LiveActivityIntents.swift); Open opens shopping mode.
struct ShoppingButtons: View {
    let context: ActivityViewContext<KinwallActivityAttributes>
    /// In the Dynamic Island, which is always black.
    var onDark = false
    var body: some View {
        HStack(spacing: 10) {
            if let listId = context.attributes.listId, let itemId = context.s.itemId {
                Button(intent: GotItIntent(listId: listId, itemId: itemId)) {
                    Label("Got it", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .tint(context.theme.accent)
            }
            if let link = context.attributes.link {
                Link(destination: link) { Label("Open", systemImage: "cart").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).tint(onDark ? .white : context.theme.fg)
            }
        }
        .font(.subheadline.weight(.semibold))
    }
}

// MARK: - Colors

/// The family's colors when the app had them, else Kinwall's own (web/src default scheme).
struct ActivityTheme {
    let bg: Color, fg: Color, accent: Color
    /// The Dynamic Island is always black: the dark accent reads on it.
    let accentOnDark: Color
    init(_ c: KinwallActivityAttributes.Colors?) {
        bg = Color(hex: c?.bg) ?? Color(light: "#FFFBF5", dark: "#1C1712")
        fg = Color(hex: c?.fg) ?? Color(light: "#3A2E27", dark: "#F3EAE0")
        accent = Color(hex: c?.accent) ?? Color(light: "#A5613F", dark: "#FF9E7A")
        accentOnDark = Color(hex: "#FF9E7A")!
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex, hex.count == 7, hex.first == "#", let v = Int(hex.dropFirst(), radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    init(light: String, dark: String) {
        let l = UIColor(Color(hex: light)!), d = UIColor(Color(hex: dark)!)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? d : l })
    }
}
