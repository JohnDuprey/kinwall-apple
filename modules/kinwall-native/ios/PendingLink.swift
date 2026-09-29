import Foundation

/// A link for the web app from native code in the app's process (Siri's and the Controls' App
/// Intents, native/ios/OpenIntents.swift): kept until JavaScript takes it (src/App.tsx), so one
/// that arrives while the app is still starting isn't lost, and announced to a running one.
public enum PendingLink {
    static let posted = Notification.Name("KinwallPendingLink")
    private static let lock = NSLock()
    nonisolated(unsafe) private static var link: String?

    public static func open(_ link: String) {
        lock.withLock { self.link = link }
        NotificationCenter.default.post(name: posted, object: nil)
    }

    static func take() -> String? { lock.withLock { defer { link = nil }; return link } }
}
