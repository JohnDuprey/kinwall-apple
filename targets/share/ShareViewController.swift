import Security
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Kinwall" in the share sheet: takes the shared link (or the first link in shared text) and saves
/// the recipe on it to the family's Kinwall (POST api/recipes/import-url), right here in the sheet.
/// A shared contact (a vCard) is reviewed and imported the same way (ContactImport.swift).
/// It signs in with what the app keeps in the shared Keychain group: the OAuth tokens (refreshed and
/// saved back when they're about to lapse; src/oauth.ts) or a paired device's key (src/sharedKey.ts).
final class ShareViewController: UIViewController {
  private let label = UILabel()
  private let spinner = UIActivityIndicatorView(style: .medium)
  private lazy var done = UIButton(configuration: .filled(), primaryAction: UIAction(title: "Done") { [weak self] _ in
    self?.extensionContext?.completeRequest(returningItems: nil)
  })

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    label.text = "Reading recipe…"
    label.font = .preferredFont(forTextStyle: .headline)
    label.textAlignment = .center
    label.numberOfLines = 0
    done.isHidden = true
    spinner.startAnimating()
    let stack = UIStackView(arrangedSubviews: [spinner, label, done])
    stack.axis = .vertical
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    Task { @MainActor in
      if let vcard = await ContactImport.sharedVCard(extensionContext) {
        label.text = "Reading contact…"
        let result = await ContactImport.preview(vcard)
        spinner.stopAnimating()
        spinner.isHidden = true
        switch result {
        case .failure(let failure):
          label.text = failure.message
          done.isHidden = false
        case .success(let rows):
          label.isHidden = true
          let context = extensionContext
          embed(ContactReview(rows: rows) { context?.completeRequest(returningItems: nil) })
        }
        return
      }
      let outcome: Outcome
      let link = await sharedLink()
      if let link { outcome = await Self.importRecipe(link, save: false) }
      else { outcome = .message("Share a link to a recipe page to import it into Kinwall.") }
      spinner.stopAnimating()
      spinner.isHidden = true
      switch outcome {
      case .message(let message):
        label.text = message
        done.isHidden = false
      case .saved(let reply):
        label.isHidden = true
        showPreview(reply, link: link!)
      }
    }
  }

  /// What Kinwall read from the page, to check before saving it: photo, name, times, warnings,
  /// ingredients, steps, then Import.
  private func showPreview(_ reply: Reply, link: URL) {
    embed(ImportPreview(reply: reply, save: { await Self.importRecipe(link, save: true) }) { [weak self] in
      self?.extensionContext?.completeRequest(returningItems: nil)
    })
  }

  private func embed(_ root: some View) {
    let host = UIHostingController(rootView: root)
    addChild(host)
    host.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(host.view)
    NSLayoutConstraint.activate([
      host.view.topAnchor.constraint(equalTo: view.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
    host.didMove(toParent: self)
  }

  /// The first web link shared: a URL attachment, else the first link in shared text.
  private func sharedLink() async -> URL? {
    let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
    let providers = items.flatMap { $0.attachments ?? [] }
    for p in providers where p.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
      if let url = try? await p.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, Self.isWeb(url) { return url }
    }
    var texts = items.compactMap { $0.attributedContentText?.string }
    for p in providers where p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
      if let text = try? await p.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String { texts.append(text) }
    }
    return texts.lazy.compactMap(Self.firstLink).first
  }

  static func isWeb(_ url: URL) -> Bool { url.scheme == "https" || url.scheme == "http" }

  static func firstLink(in text: String) -> URL? {
    let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    return detector?.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url).first(where: isWeb)
  }

  // MARK: Importing

  /// src/oauth.ts's Tokens (expiresAt in ms) and src/api.ts's Connection, as the app saves them.
  struct Tokens: Codable { var baseURL: URL; var clientId: String; var accessToken: String; var refreshToken: String; var expiresAt: Double; var scope: String }
  struct Connection: Codable { var baseURL: URL; var key: String }
  struct Reply: Decodable {
    struct Recipe: Decodable {
      struct Ingredient: Decodable { let text: String }
      struct Step: Decodable { let text: String }
      let name: String?; let imageUrl: String?; let servings: Int?; let prepMinutes: Int?; let totalMinutes: Int?
      let ingredients: [Ingredient]?; let steps: [Step]?
    }
    let recipe: Recipe; let warnings: [String]?; let created: Bool?
  }
  enum Outcome { case message(String), saved(Reply) }
  struct Failure: Decodable { let error: String? }

  /// Reads the recipe on the page (save: false, for the preview) or saves it: the recipe, or what went wrong.
  static func importRecipe(_ link: URL, save: Bool) async -> Outcome {
    do {
      guard let (data, status) = try await post("api/recipes/import-url", ["url": link.absoluteString, "save": save], timeout: 45) else { return .message("Open Kinwall and sign in, then share again.") }
      if status == 200, let r = try? JSONDecoder().decode(Reply.self, from: data) {
        return .saved(r)
      }
      let error = (try? JSONDecoder().decode(Failure.self, from: data))?.error
      let message: String = switch status {
      case 401: "Open Kinwall and sign in again, then share again."
      case 403: "Ask a grown-up to import this recipe."
      case 400: "Kinwall can only import public web pages."
      case 502: "Kinwall couldn't load that page. Try again later."
      case 422: error ?? "This page has no recipe Kinwall can read."
      default: "Couldn't import the recipe: \(error ?? "error \(status)")."
      }
      return .message(message)
    } catch is SignInNeeded {
      return .message("Open Kinwall and sign in again, then share again.")
    } catch {
      return .message("Can't reach Kinwall. Check your connection and try again.")
    }
  }

  struct SignInNeeded: Error {}

  /// POSTs JSON to the family's server, signed in: the reply and its status, or nil when signed out.
  static func post(_ path: String, _ body: Any, timeout: TimeInterval) async throws -> (Data, Int)? {
    guard let (baseURL, key) = try await credential() else { return nil }
    var req = URLRequest(url: baseURL.appending(path: path), timeoutInterval: timeout)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await URLSession.shared.data(for: req)
    return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
  }

  /// The server and a key: the OAuth access token (refreshed first if it's about to lapse; refresh
  /// tokens rotate, so the new ones are saved before use), else the paired key. Nil when signed out.
  static func credential() async throws -> (URL, String)? {
    if let data = Keychain.get("family.kinwall.oauth"), var t = try? JSONDecoder().decode(Tokens.self, from: data) {
      if t.expiresAt - Date.now.timeIntervalSince1970 * 1000 < 5 * 60_000 {
        var req = URLRequest(url: t.baseURL.appending(path: "oauth/token"), timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form: [(String, String)] = [("grant_type", "refresh_token"), ("refresh_token", t.refreshToken), ("client_id", t.clientId)]
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        req.httpBody = Data(form.map { "\($0)=\($1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }.joined(separator: "&").utf8)
        struct TokenReply: Decodable { let access_token: String; let refresh_token: String; let expires_in: Double; let scope: String }
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 400 || status == 401 { throw SignInNeeded() } // the grant is gone (revoked, expired or used)
        guard status == 200, let r = try? JSONDecoder().decode(TokenReply.self, from: data) else { throw URLError(.badServerResponse) }
        t.accessToken = r.access_token
        t.refreshToken = r.refresh_token
        t.expiresAt = (Date.now.timeIntervalSince1970 + r.expires_in) * 1000
        t.scope = r.scope
        Keychain.set("family.kinwall.oauth", try JSONEncoder().encode(t))
      }
      return (t.baseURL, t.accessToken)
    }
    if let data = Keychain.get("family.kinwall.share"), let c = try? JSONDecoder().decode(Connection.self, from: data) { return (c.baseURL, c.key) }
    return nil
  }
}

/// The app's items in the shared Keychain group (modules/kinwall-native's Keychain.query layout).
enum Keychain {
  static func query(_ service: String) -> [String: Any] {
    var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "household"]
    if let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String, !prefix.isEmpty, !prefix.hasPrefix("$(") {
      q[kSecAttrAccessGroup as String] = prefix + "family.kinwall.shared"
    }
    return q
  }
  static func get(_ service: String) -> Data? {
    var q = query(service)
    q[kSecReturnData as String] = true
    q[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: CFTypeRef?
    return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
  }
  static func set(_ service: String, _ data: Data) {
    let attrs: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
    SecItemUpdate(query(service) as CFDictionary, attrs as CFDictionary)
  }
}

/// The saved recipe as Kinwall read it, with anything it had trouble with up top.
struct ImportPreview: View {
  let reply: ShareViewController.Reply
  let save: () async -> ShareViewController.Outcome
  let onDone: () -> Void
  @State private var saving = false
  @State private var result: String?

  var body: some View {
    let r = reply.recipe
    let ingredients = r.ingredients ?? []
    let steps = r.steps ?? []
    NavigationStack {
      List {
        Section {
          if let s = r.imageUrl, let url = URL(string: s) {
            AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Color.secondary.opacity(0.15) }
              .frame(height: 180).frame(maxWidth: .infinity).clipped()
              .listRowInsets(EdgeInsets())
          }
          VStack(alignment: .leading, spacing: 4) {
            Text(r.name ?? "Recipe").font(.title3.bold())
            if !meta.isEmpty { Text(meta).font(.subheadline).foregroundStyle(.secondary) }
          }
        }
        if let result { Section { Text(result).font(.headline) } }
        if let warnings = reply.warnings, !warnings.isEmpty {
          Section("Check these") {
            ForEach(warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
          }
        }
        Section("\(ingredients.count) ingredient\(ingredients.count == 1 ? "" : "s")") {
          ForEach(Array(ingredients.enumerated()), id: \.offset) { Text($0.element.text) }
        }
        Section("\(steps.count) step\(steps.count == 1 ? "" : "s")") {
          ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
              Text("\(i + 1)").font(.headline).foregroundStyle(.secondary)
              Text(step.text)
            }
          }
        }
      }
      .navigationTitle("Import to Kinwall")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if result == nil { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onDone) } }
        ToolbarItem(placement: .confirmationAction) {
          if saving { ProgressView() }
          else if result == nil { Button("Import") { Task { await importIt() } }.bold() }
          else { Button("Done", action: onDone).bold() }
        }
      }
    }
  }

  private func importIt() async {
    saving = true
    switch await save() {
    case .saved(let r): result = "\(r.created == false ? "Updated" : "Saved"): \(r.recipe.name ?? "recipe") ✓"
    case .message(let m): result = m
    }
    saving = false
  }

  private var meta: String {
    let r = reply.recipe
    var parts: [String] = []
    if let n = r.servings { parts.append("Serves \(n)") }
    if let m = r.prepMinutes { parts.append("Prep \(m) min") }
    if let m = r.totalMinutes { parts.append("Total \(m) min") }
    return parts.joined(separator: " · ")
  }
}
