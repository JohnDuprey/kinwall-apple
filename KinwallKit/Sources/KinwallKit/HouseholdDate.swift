import Foundation

/// Kinwall's days are the household's: "today" is YYYY-MM-DD in the household timezone
/// (Settings.timezone), not the device's, so a phone travelling abroad still ticks today's chores.
public enum HouseholdDate {
    public static func key(for date: Date = .now, timezone: String?) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone.flatMap(TimeZone.init(identifier:)) ?? .current
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
