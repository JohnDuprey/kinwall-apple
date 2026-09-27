import SwiftUI
import KinwallKit
import UserNotifications

/// The iPhone and iPad app: the household's own Kinwall web app, full screen, in a native frame
/// (docs/PLAN.md). First launch asks for the server, then signs in (OAuth in a Safari sheet, or a
/// pairing code). The server can also be changed in the iOS Settings app, which `ServerAddress` reads.
@main
struct KinwallApp: App {
    @State private var server = ServerAddress.current
    @State private var session = Session(server: ServerAddress.current)
    @State private var route: String? // a tab to show, from a widget link
    @Environment(\.scenePhase) private var phase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationRouter.shared
        WatchLink.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let url = server {
                    if session.mode == nil {
                        SignInView(server: url, session: session, onChangeServer: changeServer)
                    } else {
                        WebShell(url: url, session: session, route: $route, onChangeServer: changeServer)
                    }
                } else {
                    ServerEntryView { url in ServerAddress.save(url); server = url; session = Session(server: url) }
                }
            }
            // Widget links: family.kinwall.app:/open?to=chores (or calendar, lists), plus &done=<chore id>
            // to tap that chore in the web app (it asks "Who did it?" or opens the checklist).
            .onOpenURL { url in
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                guard url.path == "/open", let to = query.first(where: { $0.name == "to" })?.value,
                      ["calendar", "chores", "lists"].contains(to) else { return }
                // The id lands in page script, so only plain id characters pass.
                if to == "chores", let done = query.first(where: { $0.name == "done" })?.value,
                   !done.isEmpty, done.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) {
                    route = "chores?done=\(done)"
                } else {
                    route = to
                }
            }
            // A tapped reminder opens its event.
            .onAppear { NotificationRouter.shared.listen { route = $0 } }
            // Reminders are rescheduled each time the app opens or goes to the background.
            .onChange(of: phase) { _, now in
                if now == .background { Reminders.scheduleBackgroundRefresh() }
                if now != .inactive { Task { await Reminders.refresh() } }
                // Picks up a server change made in the Settings app while Kinwall was in the background.
                guard now == .active, ServerAddress.current != server else { return }
                server = ServerAddress.current
                session = Session(server: server)
            }
        }
        // A few times a day, so reminders for events added elsewhere are scheduled even if the app isn't opened.
        .backgroundTask(.appRefresh(Reminders.refreshTask)) {
            await Reminders.refresh()
            Reminders.scheduleBackgroundRefresh()
        }
    }

    private func changeServer() {
        Task { await session.signOut(); ServerAddress.clear(); server = nil }
    }
}
