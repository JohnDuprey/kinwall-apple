import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A contact shared from Contacts (or any app that shares a vCard): the family's server reads it and
/// marks possible duplicates (POST api/contacts/import/preview), the person picks what to do with
/// each, and Import saves them (POST api/contacts/import), as the web app's Contacts → Import does.
/// All in the sheet: an extension can't hand data to the app without an App Group, which a free
/// Personal Team doesn't have.
enum ContactImport {
  struct Failure: Error { let message: String }

  /// One contact to review: the server's draft (sent back as is), its duplicates, and the choice.
  struct Row: Identifiable {
    let id: Int
    let contact: [String: Any]
    let duplicateIds: [String]
    var decision: Decision
    var name: String { contact["name"] as? String ?? "Contact" }
    var initials: String { name.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined().uppercased() }
    /// Nickname, job title and company (when it isn't the name), under the name.
    var subtitle: String {
      let org = contact["organization"] as? String
      return [(contact["nickname"] as? String).map { "“\($0)”" }, contact["title"] as? String, org == name ? nil : org]
        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    /// What the card brought in, grouped like the web app's review: phones, emails, addresses and
    /// websites, then dates, tags and notes. Each line is (label, value); the label may be empty.
    var groups: [(title: String, lines: [(String, String)])] {
      let list = { (key: String) in contact[key] as? [[String: Any]] ?? [] }
      let values = { (key: String) in list(key).compactMap { d in (d["value"] as? String).map { (ContactImport.label(d["label"]), $0) } } }
      // Emails and links wrap after their dots and @ instead of hyphenating ("exam-ple.org").
      let breakable = { (lines: [(String, String)]) in lines.map { ($0.0, $0.1.replacingOccurrences(of: ".", with: ".\u{200B}").replacingOccurrences(of: "@", with: "@\u{200B}")) } }
      let addresses = list("addresses").map { a in
        let s = { (k: String) in a[k] as? String ?? "" }
        let town = [[s("city"), s("region")].filter { !$0.isEmpty }.joined(separator: ", "), s("postalCode")].filter { !$0.isEmpty }.joined(separator: " ")
        let line = [s("street"), town, s("country")].filter { !$0.isEmpty }.joined(separator: "\n")
        return (ContactImport.label(a["label"]), line)
      }
      let dates = list("dates").compactMap { d in (d["date"] as? String).map { (ContactImport.label(d["label"]), ContactImport.date($0)) } }
      let tags = (contact["tags"] as? [String] ?? []).joined(separator: ", ")
      let notes = contact["notes"] as? String ?? ""
      return [("Phone", values("phones")), ("Email", breakable(values("emails"))), ("Address", addresses), ("Websites", breakable(values("websites"))), ("Dates", dates),
              ("Tags", tags.isEmpty ? [] : [("", tags)]), ("Notes", notes.isEmpty ? [] : [("", notes)])].filter { !$0.lines.isEmpty }
    }
  }

  /// "birthday" → "Birthday"; the server already turns vCard types into words ("Mobile", "Work fax").
  static func label(_ any: Any?) -> String {
    let l = (any as? String ?? "").trimmingCharacters(in: .whitespaces)
    return l.prefix(1).uppercased() + l.dropFirst()
  }

  /// "1952-03-14" → "March 14, 1952"; "--11-02" (no year) → "November 2".
  static func date(_ s: String) -> String {
    let p = s.split(separator: "-", omittingEmptySubsequences: true).compactMap { Int($0) }
    let noYear = s.hasPrefix("--")
    guard p.count == (noYear ? 2 : 3) else { return s }
    var c = DateComponents(); c.year = noYear ? 2000 : p[0]; c.month = p[p.count - 2]; c.day = p[p.count - 1]
    guard let d = Calendar(identifier: .gregorian).date(from: c) else { return s }
    let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate(noYear ? "MMMMd" : "yMMMMd")
    return f.string(from: d)
  }

  /// The web app's choices: a new contact is added or skipped; a possible duplicate is skipped
  /// (the default), merged into the saved one, or kept as a second contact.
  enum Decision: String, CaseIterable { case add, skip, merge, keep
    var label: String { switch self { case .add: "Add this contact"; case .skip: "Skip it"; case .merge: "Update the saved contact"; case .keep: "Add as a separate contact" } }
  }

  /// The shared vCards' text, photos left out, or nil when nothing shared is a vCard. A vCard shared
  /// as plain text counts too, so its URL: line isn't taken for a recipe link.
  static func sharedVCard(_ context: NSExtensionContext?) async -> String? {
    let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
    var cards: [String] = []
    for p in providers {
      let type = p.hasItemConformingToTypeIdentifier(UTType.vCard.identifier) ? UTType.vCard : p.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) ? UTType.plainText : nil
      guard let type else { continue }
      let data: Data? = await withCheckedContinuation { done in
        _ = p.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in done.resume(returning: data) }
      }
      if let data, let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1), text.range(of: "BEGIN:VCARD", options: .caseInsensitive) != nil { cards.append(text) }
    }
    return cards.isEmpty ? nil : withoutPhotos(cards.joined(separator: "\r\n"))
  }

  /// Kinwall ignores photos, and they're most of a card's size: drops PHOTO, LOGO, SOUND and KEY
  /// properties with their folded lines (the ones starting with a space or tab). Same as the app's
  /// src/links.ts importContactsScript.
  static func withoutPhotos(_ vcard: String) -> String {
    vcard.replacingOccurrences(of: #"(?im)^(PHOTO|LOGO|SOUND|KEY)[;:].*(\r?\n[ \t].*)*\r?\n"#, with: "", options: .regularExpression)
  }

  static func message(_ status: Int, _ data: Data, action: String) -> String {
    let error = (try? JSONDecoder().decode(ShareViewController.Failure.self, from: data))?.error
    return switch status {
    case 401: "Open Kinwall and sign in again, then share again."
    case 403: "Ask a parent to add contacts to Kinwall."
    case 400: error ?? "Kinwall couldn't read that contact."
    case 404: "This Kinwall doesn't have Contacts. Update it, or turn Contacts on in Settings."
    default: "Couldn't \(action): \(error ?? "error \(status)")."
    }
  }

  /// The server's reading of the vCard, one row per contact, or what went wrong.
  static func preview(_ vcard: String) async -> Result<[Row], Failure> {
    guard vcard.utf8.count <= 2_000_000 else { return .failure(Failure(message: "That's too much to import at once. Share fewer contacts.")) }
    do {
      guard let (data, status) = try await ShareViewController.post("api/contacts/import/preview", ["vcard": vcard], timeout: 30) else {
        return .failure(Failure(message: "Open Kinwall and sign in, then share again."))
      }
      guard status == 200 else { return .failure(Failure(message: message(status, data, action: "read the contact"))) }
      let entries = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["entries"] as? [[String: Any]] ?? []
      let rows = entries.enumerated().compactMap { i, entry -> Row? in
        guard let contact = entry["contact"] as? [String: Any] else { return nil }
        let dupes = entry["duplicateIds"] as? [String] ?? []
        return Row(id: i, contact: contact, duplicateIds: dupes, decision: dupes.isEmpty ? .add : .skip)
      }
      if rows.isEmpty { return .failure(Failure(message: "No contacts with names were found.")) }
      if rows.count > 500 { return .failure(Failure(message: "Share up to 500 contacts at a time.")) }
      return .success(rows)
    } catch is ShareViewController.SignInNeeded {
      return .failure(Failure(message: "Open Kinwall and sign in again, then share again."))
    } catch {
      return .failure(Failure(message: "Can't reach Kinwall. Check your connection and try again."))
    }
  }

  /// Saves the rows not skipped: new ones and "Keep both" as new contacts, then the merges into the
  /// contact each matched. What happened, for the sheet.
  static func save(_ rows: [Row]) async -> String {
    let creates = rows.filter { $0.decision == .add || $0.decision == .keep }
    let merges = rows.filter { $0.decision == .merge && !$0.duplicateIds.isEmpty }
    do {
      if !creates.isEmpty {
        guard let (data, status) = try await ShareViewController.post("api/contacts/import", ["contacts": creates.map(\.contact), "strategy": "create"], timeout: 30) else { return "Open Kinwall and sign in, then share again." }
        if status != 200 { return message(status, data, action: "import") }
      }
      if !merges.isEmpty {
        guard let (data, status) = try await ShareViewController.post("api/contacts/import", ["contacts": merges.map(\.contact), "strategy": "merge", "mergeTargets": merges.map { $0.duplicateIds[0] }, "confirmMerge": true], timeout: 30) else { return "Open Kinwall and sign in, then share again." }
        if status != 200 { return message(status, data, action: "merge") }
      }
    } catch is ShareViewController.SignInNeeded {
      return "Open Kinwall and sign in again, then share again."
    } catch {
      return "Can't reach Kinwall. Check your connection and try again."
    }
    let saved = creates.count + merges.count
    if saved == 1 { return "Saved: \((creates.first ?? merges.first)!.name) ✓" }
    return "Saved \(saved) contacts ✓"
  }
}

/// Each shared contact laid out like its contact sheet: initials, name, nickname, title and company
/// with New or Already in Kinwall?, then its phones, emails, addresses, websites, dates, tags and
/// notes with their labels, then what to do with it. Cancel and Save in the toolbar.
struct ContactReview: View {
  @State var rows: [ContactImport.Row]
  let onDone: () -> Void
  @State private var saving = false
  @State private var result: String?

  var body: some View {
    let count = rows.filter { $0.decision != .skip }.count
    NavigationStack {
      List {
        if rows.count > 1 {
          Section { Text("\(rows.count) contacts to review. One with the same phone, email or name as a saved contact is marked Already in Kinwall?").font(.subheadline).foregroundStyle(.secondary) }
        }
        if let result { Section { Text(result).font(.headline) } }
        ForEach($rows) { $row in
          Section {
            HStack(spacing: 14) {
              Text(row.initials).font(.title3.bold()).foregroundStyle(.tint)
                .frame(width: 56, height: 56).background(Circle().fill(.tint.opacity(0.15)))
                .accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 4) {
                Text(row.name).font(.title3.bold())
                if !row.subtitle.isEmpty { Text(row.subtitle).font(.subheadline).foregroundStyle(.secondary) }
                // An HStack, not a Label: in a List row a Label's icon sits in its own wide column.
                HStack(spacing: 4) {
                  Image(systemName: row.duplicateIds.isEmpty ? "plus.circle" : "exclamationmark.triangle.fill")
                  Text(row.duplicateIds.isEmpty ? "New contact" : "Already in Kinwall?")
                }
                .font(.caption.bold()).foregroundStyle(row.duplicateIds.isEmpty ? .green : .orange)
              }
            }
            .padding(.vertical, 4)
            ForEach(row.groups, id: \.title) { group in
              VStack(alignment: .leading, spacing: 8) {
                Text(group.title.uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(Array(group.lines.enumerated()), id: \.offset) { _, line in
                  HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if !line.0.isEmpty { Text(line.0).font(.subheadline).foregroundStyle(.secondary).frame(width: 96, alignment: .leading) }
                    Text(line.1).fixedSize(horizontal: false, vertical: true)
                  }
                }
              }
              .padding(.vertical, 2)
            }
            Picker(row.duplicateIds.isEmpty ? "Add to Kinwall" : "What to do", selection: $row.decision) {
              ForEach(row.duplicateIds.isEmpty ? [.add, .skip] : [.skip, .merge, .keep] as [ContactImport.Decision], id: \.self) { Text($0.label).tag($0) }
            }
            .disabled(saving || result != nil)
          }
        }
      }
      .navigationTitle(rows.count == 1 ? "Import contact" : "Review contacts")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if result == nil { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onDone) } }
        ToolbarItem(placement: .confirmationAction) {
          if saving { ProgressView() }
          else if result == nil { Button(rows.count == 1 ? (rows[0].decision == .merge ? "Update" : "Save") : "Save \(count)") { Task { await importIt() } }.bold().disabled(count == 0) }
          else { Button("Done", action: onDone).bold() }
        }
      }
    }
  }

  private func importIt() async {
    saving = true
    result = await ContactImport.save(rows)
    saving = false
  }
}
