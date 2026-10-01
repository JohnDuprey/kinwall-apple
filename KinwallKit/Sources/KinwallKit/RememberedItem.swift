import Foundation

/// One name in the family's groceries catalog (GET /api/lists/remembered), for Siri's one-sentence
/// "Add milk to Kinwall" (native/ios/SiriIntents.swift ItemEntity).
public struct RememberedItem: Codable, Hashable, Sendable {
    public let title: String
    /// Times added to a shopping list (0: added to the catalog only).
    public let uses: Int
    public let lastUsed: String?
    public init(title: String, uses: Int, lastUsed: String?) { self.title = title; self.uses = uses; self.lastUsed = lastUsed }

    /// The title without emoji, what Siri hears: "Milk 🥛" is "Milk".
    public var plainName: String {
        String(String.UnicodeScalarView(title.unicodeScalars.filter {
            !($0.properties.isEmojiPresentation || $0.properties.isEmojiModifier || ($0.properties.isEmoji && $0.value > 0x238C) || $0.value == 0xFE0F || $0.value == 0x200D)
        })).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// App Shortcut phrases are capped at 1,000 per app, every parameter value counting once per
    /// phrase that holds it. Item phrases × this cap (2 × 300) leaves room for the lists, stores
    /// and chores phrases.
    public static let siriCap = 300

    /// The most used first (then the most recent), at most `cap`, each plain name once.
    public static func forSiri(_ items: [RememberedItem], cap: Int = siriCap) -> [RememberedItem] {
        var seen = Set<String>()
        return items
            .sorted { ($0.uses, $0.lastUsed ?? "") > ($1.uses, $1.lastUsed ?? "") }
            .filter { !$0.plainName.isEmpty && seen.insert($0.plainName.lowercased()).inserted }
            .prefix(cap).map { $0 }
    }

    /// The items whose plain name holds `text`, case and emoji ignored.
    public static func matching(_ text: String, in items: [RememberedItem]) -> [RememberedItem] {
        let wanted = RememberedItem(title: text, uses: 0, lastUsed: nil).plainName
        return items.filter { $0.plainName.localizedCaseInsensitiveContains(wanted) }
    }
}
