import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

// The Live Activities (modules/kinwall-native/ios/LiveActivities.swift starts them; the web app
// decides what they say): a cooking timer, a shopping trip, and the next leave-by or start-prep
// time, on the Lock Screen and in the Dynamic Island. Countdowns tick on their own
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
                        if let line = context.islandLine { Text(line).font(.subheadline).foregroundStyle(.secondary).lineLimit(1) }
                        if context.attributes.kind == "shopping" { ShoppingButtons(context: context, onDark: true) }
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
    var icon: String { ["cooking": "⏲️", "shopping": "🛒", "leave": "🚗", "prep": "🍳"][kind] ?? "📅" }
    /// Open: shopping mode for a trip, the calendar for a leave-by; the app as it was for cooking.
    var link: URL? {
        switch kind {
        case "shopping": listId.flatMap { URL(string: "family.kinwall.app:/open?to=lists/\($0)/shop") }
        case "leave", "prep": URL(string: "family.kinwall.app:/open?to=calendar")
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
        default: due ? (s.detail ?? "Time to go") : s.title
        }
    }

    var subline: String {
        switch attributes.kind {
        case "cooking": [s.detail, s.count > 0 ? "+\(s.count) more" : nil, attributes.name].compactMap { $0 }.joined(separator: " · ") // the step first; the recipe fits if it can
        // "Shaws · 5 left · next: Dairy"
        case "shopping": [attributes.name, "\(s.count) left", s.detail.map { "next: \($0)" }].compactMap { $0 }.joined(separator: " · ")
        default: attributes.name
        }
    }

    /// The expanded island's second line (its leading region already names the recipe, store or event).
    var islandLine: String? {
        switch attributes.kind {
        case "cooking": [s.detail, s.count > 0 ? "+\(s.count) more" : nil].compactMap { $0 }.joined(separator: " · ")
        case "shopping": ["\(s.count) left", s.detail.map { "next: \($0)" }].compactMap { $0 }.joined(separator: " · ")
        default: nil
        }
    }

    var theme: ActivityTheme { ActivityTheme(attributes.colors) }
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
            if context.attributes.kind == "shopping" { ShoppingButtons(context: context) }
        }
        .padding(16)
    }

    /// Leave / prep: "Soccer practice · leave in" before the countdown; the others: their subline.
    private var lead: String {
        switch context.attributes.kind {
        case "leave": context.due ? context.attributes.name : "\(context.attributes.name) · leave in"
        case "prep": context.due ? context.attributes.name : "\(context.attributes.name) · start prep in"
        // The count is on the right: "Shaws · next: Dairy".
        case "shopping": [context.attributes.name, context.s.detail.map { "next: \($0)" }].compactMap { $0 }.joined(separator: " · ")
        default: context.subline
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
