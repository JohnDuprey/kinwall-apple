import Foundation
#if canImport(Security)
import Security
#endif

/// The Keychain group the app and its widgets share (keychain-access-groups in app.json and targets/*/expo-target.config.js), and
/// the widget key kept in it. The group needs the team prefix, which each target's Info.plist
/// exposes as AppIdentifierPrefix.
public enum SharedKeychain {
    public static var group: String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
              !prefix.isEmpty, !prefix.hasPrefix("$(") else { return nil }
        return prefix + "family.kinwall.shared"
    }

    #if canImport(Security)
    /// The widgets' own everyday-access key (never the app's rotating sign-in).
    public static var widgetStore: KeychainConnectionStore {
        KeychainConnectionStore(service: "family.kinwall.widgets", accessGroup: group)
    }

    /// Set by the app while the demo family is open (src/demo.ts), cleared when it closes. The
    /// widgets then show bundled sample data, but only while `widgetStore` is empty: a real family
    /// always wins.
    public static var demoStore: KeychainConnectionStore {
        KeychainConnectionStore(service: "family.kinwall.demo", accessGroup: group)
    }
    #endif
}

/// The Kinwall Focus filter (native/ios/FocusFilter.swift, iPhone Settings → Focus → a Focus →
/// Focus filters) as the widgets read it: kept in the shared Keychain group, like the widgets' key,
/// so no App Group is needed. Nothing saved = no filter.
public struct FocusSettings: Codable, Equatable, Sendable {
    /// Only this device's person's events (and family ones nobody is tagged in).
    public var onlyMine: Bool
    /// Hide the health widgets (Take now, Check-in, Energy).
    public var hideHealth: Bool
    /// This device's person when the filter was set (GET /api/me); nil on a shared device.
    public var person: String?
    public init(onlyMine: Bool, hideHealth: Bool, person: String?) { self.onlyMine = onlyMine; self.hideHealth = hideHealth; self.person = person }

    /// Does an event with these people pass? Family events (nobody tagged) always do, and so does
    /// everything on a device that isn't a person's own.
    public func shows(_ memberIds: [String]) -> Bool {
        guard onlyMine, let person, !memberIds.isEmpty else { return true }
        return memberIds.contains(person)
    }

    #if canImport(Security)
    private static var query: [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "family.kinwall.focus", kSecAttrAccount as String: "household"]
        if let group = SharedKeychain.group { q[kSecAttrAccessGroup as String] = group }
        return q
    }

    /// The Focus filter now in effect, or nil (no Focus, or one without Kinwall's filter).
    public static func current() -> FocusSettings? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(FocusSettings.self, from: data)
    }

    /// nil clears it (the Focus ended, or its filter is all off).
    public static func save(_ settings: FocusSettings?) {
        guard let settings, settings.onlyMine || settings.hideHealth, let data = try? JSONEncoder().encode(settings) else { SecItemDelete(query as CFDictionary); return }
        let attrs: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        if SecItemUpdate(query as CFDictionary, attrs as CFDictionary) == errSecItemNotFound { SecItemAdd(query.merging(attrs) { $1 } as CFDictionary, nil) }
    }
    #endif
}
