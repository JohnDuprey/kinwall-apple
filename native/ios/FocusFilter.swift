import AppIntents
import KinwallKit
import WidgetKit

/// The Kinwall Focus filter (iPhone Settings → Focus → a Focus → Add Filter → Kinwall). iOS runs
/// it when that Focus turns on, and again with everything off when it ends.
/// - Only my reminders: someone else's event reminders stay quiet (the app tags them "others",
///   modules/kinwall-native/ios/Reminders.swift), and Now & Next and Today show only this device's
///   person's events and family ones nobody is tagged in. Medicine and chore reminders are already
///   only theirs. A shared device (no person) is left as it is.
/// - Hide health widgets: Take now, Check-in and Energy show "Hidden during this Focus".
/// Saved in the shared Keychain group (KinwallKit FocusSettings), which the widgets read.
struct KinwallFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Kinwall"
    static let description: IntentDescription? = "Choose what Kinwall shows during this Focus."

    @Parameter(title: "Only my reminders", description: "Quiet reminders for other people's events, and show only your events and family ones in Now & Next and Today.", default: false)
    var onlyMine: Bool
    @Parameter(title: "Hide health widgets", description: "Take now, Check-in and Energy.", default: false)
    var hideHealth: Bool

    var displayRepresentation: DisplayRepresentation {
        let on = [onlyMine ? "Only my reminders" : nil, hideHealth ? "Health widgets hidden" : nil].compactMap { $0 }
        return DisplayRepresentation(title: "Kinwall", subtitle: LocalizedStringResource(stringLiteral: on.isEmpty ? "Everything" : on.joined(separator: ", ")))
    }

    var appContext: FocusFilterAppContext {
        FocusFilterAppContext(notificationFilterPredicate: onlyMine ? NSPredicate(format: "SELF != %@", "others") : nil)
    }

    func perform() async throws -> some IntentResult {
        var person: String?
        if onlyMine, let connection = try? SharedKeychain.widgetStore.load() { person = try? await KinwallClient(connection).me().person }
        FocusSettings.save(FocusSettings(onlyMine: onlyMine, hideHealth: hideHealth, person: person))
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
