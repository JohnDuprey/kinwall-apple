import SwiftUI
import WebKit
import KinwallKit

/// The Kinwall web app, full screen. Tells the page it's inside the app, keeps other sites in
/// Safari, hands downloads to the share sheet, follows the page's theme color, and copies the
/// paired key to the Keychain for the widgets, Watch and Siri.
struct WebShell: View {
    let url: URL
    let session: Session
    @Binding var route: String?
    let onChangeServer: () -> Void
    @Environment(\.scenePhase) private var phase
    @State private var background = Color(uiColor: .systemBackground)
    @State private var darkPage = false
    @State private var failed: String?
    @State private var share: URL?
    @State private var reloadToken = 0

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            if let failed {
                ContentUnavailableView {
                    Label("Can't reach Kinwall", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(failed)
                } actions: {
                    Button("Try again") { self.failed = nil; reloadToken += 1 }.buttonStyle(.borderedProminent)
                    Button("Change server", action: onChangeServer)
                }
            } else {
                KinwallWebView(url: url, reloadToken: reloadToken, route: $route, accessToken: session.mode == .oauth ? session.accessToken : nil,
                               onTheme: { color in background = Color(uiColor: color); darkPage = color.isDark },
                               onFail: { failed = $0 }, onDownload: { share = $0 }, onSignedOut: signedOut,
                               startsPairing: session.mode == .paired && (try? SharedKeychain.widgetStore.load()) == nil)
                    .ignoresSafeArea() // the page lays itself out with env(safe-area-inset-*)
            }
        }
        .statusBarHidden(true) // the page uses the full screen; the web app drops its status-bar gap in the app
        .preferredColorScheme(darkPage ? .dark : .light) // keeps system sheets (share, pickers) matching the page
        .sheet(item: $share) { ShareSheet(items: [$0]) }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = UIDevice.current.userInterfaceIdiom == .pad } // a wall iPad stays awake
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        // OAuth keys last an hour: refresh ahead of time while the app is open, and on every return.
        .task(id: phase) {
            guard phase == .active, session.mode == .oauth else { return }
            while !Task.isCancelled {
                if await session.freshToken() == nil { await session.signOut(); return }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    /// The page cleared its key. `rejected` (a 401): after a sleep the OAuth key may simply have
    /// lapsed, so refresh and carry on. `signOut` (the person chose it), or a refresh that fails:
    /// end the session and go back to the sign-in screen.
    private func signedOut(reason: String) {
        Task {
            if reason == "rejected", session.mode == .oauth, await session.freshToken() != nil { reloadToken += 1; return }
            await session.signOut()
        }
    }
}

extension URL: @retroactive Identifiable { public var id: String { absoluteString } }

private extension UIColor {
    var isDark: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.5
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct KinwallWebView: UIViewRepresentable {
    let url: URL
    let reloadToken: Int
    @Binding var route: String?
    /// With OAuth, the key the page should use (it reads localStorage 'kinwall.apiKey' on every
    /// request). Nil when paired: the page keeps its own key.
    let accessToken: String?
    let onTheme: (UIColor) -> Void
    let onFail: (String) -> Void
    let onDownload: (URL) -> Void
    let onSignedOut: (_ reason: String) -> Void
    /// Chose "Pair with a code": open the page on its pairing code (web/src/App.tsx reads ?start=pair).
    var startsPairing = false
    private var startURL: URL { startsPairing ? url.appending(queryItems: [URLQueryItem(name: "start", value: "pair")]) : url }

    /// Read by the web app to adapt (hide the Add to Home Screen card and web push, which don't
    /// apply inside the app). Keep in sync with web/src/native.ts in the kinwall repo.
    static let bridgeScript = """
    window.kinwallNative = { platform: 'ios', version: '\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")' };
    """

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // keeps the paired key and settings between launches
        config.applicationNameForUserAgent = "KinwallApp/\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")"
        config.allowsInlineMediaPlayback = true
        config.userContentController.add(context.coordinator, name: "kinwall") // messages from web/src/native.ts
        context.coordinator.installScripts(config.userContentController, token: accessToken)
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.contentInsetAdjustmentBehavior = .never // the page handles the notch and home indicator
        web.scrollView.bounces = false
        web.allowsLinkPreview = false
        #if DEBUG
        web.isInspectable = true // Safari → Develop → Simulator
        #endif
        context.coordinator.themeObservation = web.observe(\.themeColor, options: [.initial, .new]) { web, _ in
            MainActor.assumeIsolated { if let color = web.themeColor { onTheme(color) } } // KVO fires on the main thread
        }
        web.load(URLRequest(url: startURL))
        context.coordinator.loadedToken = reloadToken
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let c = context.coordinator
        c.parent = self
        if c.injectedToken != accessToken, let accessToken {
            // A refreshed key: into the running page now, and into the script for the next load.
            c.installScripts(web.configuration.userContentController, token: accessToken)
            web.evaluateJavaScript("localStorage.setItem('kinwall.apiKey', \(Coordinator.jsString(accessToken)))")
        }
        if c.loadedToken != reloadToken {
            c.loadedToken = reloadToken
            web.load(URLRequest(url: url))
        }
        if let route {
            // Still loading (a cold start from a widget): go there once the page is up.
            if web.isLoading { c.pendingRoute = route } else { Coordinator.go(web, to: route) }
            DispatchQueue.main.async { self.route = nil }
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, WKScriptMessageHandler {
        var parent: KinwallWebView
        var themeObservation: NSKeyValueObservation?
        var loadedToken = 0
        var pendingRoute: String?

        static func go(_ web: WKWebView, to route: String) { web.evaluateJavaScript("location.hash = \(jsString("#/" + route))") }
        private(set) var injectedToken: String?

        /// The bridge flag, plus (with OAuth) the key, set before the page's own scripts run.
        func installScripts(_ ucc: WKUserContentController, token: String?) {
            ucc.removeAllUserScripts()
            var source = KinwallWebView.bridgeScript
            if let token { source += "\ntry { localStorage.setItem('kinwall.apiKey', \(Self.jsString(token))) } catch (e) {}" }
            ucc.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            injectedToken = token
        }

        static func jsString(_ s: String) -> String {
            let data = try? JSONSerialization.data(withJSONObject: [s])
            return data.flatMap { String(data: $0, encoding: .utf8) }.map { String($0.dropFirst().dropLast()) } ?? "''"
        }

        // web/src/native.ts posts { type: 'signedOut' } when the page clears its key.
        func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            switch body["type"] as? String {
            case "signedIn": if let web = message.webView { syncKey(web) }
            case "signedOut": parent.onSignedOut(body["reason"] as? String ?? "signOut")
            default: break
            }
        }
        private var downloadFile: URL?

        init(_ parent: KinwallWebView) { self.parent = parent }

        private func isKinwall(_ url: URL?) -> Bool { url?.host() == parent.url.host() }

        // Other sites (docs, maps, sign-in pages) open in Safari; Kinwall stays here.
        func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let target = action.request.url else { return .cancel }
            if ["tel", "mailto", "sms", "maps"].contains(target.scheme ?? "") || (!isKinwall(target) && ["http", "https"].contains(target.scheme ?? "")) {
                if action.targetFrame?.isMainFrame != false { await UIApplication.shared.open(target); return .cancel }
            }
            return action.shouldPerformDownload ? .download : .allow
        }

        func webView(_ web: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
            response.canShowMIMEType ? .allow : .download
        }

        // target="_blank" (e.g. the Help button's docs links): Safari.
        func webView(_ web: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let target = action.request.url {
                if isKinwall(target) { web.load(action.request) } else { UIApplication.shared.open(target) }
            }
            return nil
        }

        // alert/confirm from the page (the web app uses its own dialogs, but be safe).
        func webView(_ web: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {}
        func webView(_ web: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool { false }

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            syncKey(web)
            if let route = pendingRoute { pendingRoute = nil; Self.go(web, to: route) }
        }

        func webView(_ web: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let e = error as NSError
            if e.code == NSURLErrorCancelled || e.domain == "WebKitErrorDomain" { return } // our own cancels and download hand-offs
            parent.onFail(e.localizedDescription)
        }

        // Downloads (the photo zip, a saved drawing): into a temp file, then the share sheet.
        func webView(_ web: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
        func webView(_ web: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
            let file = FileManager.default.temporaryDirectory.appending(path: suggestedFilename)
            try? FileManager.default.removeItem(at: file)
            downloadFile = file
            return file
        }
        func downloadDidFinish(_ download: WKDownload) { if let downloadFile { parent.onDownload(downloadFile) } }

        /// Once the page is signed in (its key is in localStorage 'kinwall.apiKey'), make sure the
        /// widgets have their own everyday-access key: created with the page's key, kept in the
        /// Keychain group the widget extension shares. Never the app's rotating sign-in itself.
        private func syncKey(_ web: WKWebView) {
            web.evaluateJavaScript("localStorage.getItem('kinwall.apiKey')") { [parent] value, _ in
                guard let key = value as? String, !key.isEmpty else { return }
                Task {
                    await WidgetKey.ensure(server: parent.url, using: key)
                    await Reminders.requestPermission() // first time signed in: ask, then schedule
                    await Reminders.refresh()
                    await WatchLink.shared.sync()
                }
            }
        }
    }
}
