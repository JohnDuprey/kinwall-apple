import CoreSpotlight
import UniformTypeIdentifiers

/// The family's recipes, lists and contacts in Spotlight (src/spotlight.ts decides what; names and
/// a short line only). Each item's identifier is the app link it opens, which AppHooks
/// (native/ios/AppHooks.swift) hands to the web app when a result is tapped. One domain, so a
/// sync replaces everything and sign-out clears it.
enum Spotlight {
    static let domain = "family.kinwall.app.family"

    static func replace(_ items: [[String: String]]) async throws {
        let index = CSSearchableIndex.default()
        try await index.deleteSearchableItems(withDomainIdentifiers: [domain])
        let searchable = items.compactMap { item -> CSSearchableItem? in
            guard let id = item["id"], let title = item["title"] else { return nil }
            let attributes = CSSearchableItemAttributeSet(contentType: .content)
            attributes.title = title
            attributes.contentDescription = item["description"]
            attributes.keywords = [item["kind"], "Kinwall"].compactMap { $0 }
            return CSSearchableItem(uniqueIdentifier: id, domainIdentifier: domain, attributeSet: attributes)
        }
        try await index.indexSearchableItems(searchable)
    }

    static func clear() async throws { try await CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domain]) }
}
