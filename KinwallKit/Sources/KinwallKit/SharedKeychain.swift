import Foundation

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
    #endif
}
