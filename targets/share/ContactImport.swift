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
    var detail: String {
      let first = { (key: String) in ((contact[key] as? [[String: Any]])?.first?["value"] as? String) }
      return [first("phones"), first("emails"), contact["organization"] as? String].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
  }

  /// The web app's choices: a new contact is added or skipped; a possible duplicate is skipped
  /// (the default), merged into the saved one, or kept as a second contact.
  enum Decision: String, CaseIterable { case add, skip, merge, keep
    var label: String { switch self { case .add: "Add"; case .skip: "Skip"; case .merge: "Merge"; case .keep: "Keep both" } }
  }

  /// The shared vCards' text, photos left out, or nil when nothing shared is a vCard.
  static func sharedVCard(_ context: NSExtensionContext?) async -> String? {
    let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
      .filter { $0.hasItemConformingToTypeIdentifier(UTType.vCard.identifier) }
    guard !providers.isEmpty else { return nil }
    var cards: [String] = []
    for p in providers {
      let data: Data? = await withCheckedContinuation { done in
        _ = p.loadDataRepresentation(forTypeIdentifier: UTType.vCard.identifier) { data, _ in done.resume(returning: data) }
      }
      if let data, let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) { cards.append(text) }
    }
    return withoutPhotos(cards.joined(separator: "\r\n"))
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

/// "Add Ms. Park to Kinwall?": each shared contact, marked New or Possible duplicate, with what to
/// do with it, then Import.
struct ContactReview: View {
  @State var rows: [ContactImport.Row]
  let onDone: () -> Void
  @State private var saving = false
  @State private var result: String?

  var body: some View {
    let count = rows.filter { $0.decision != .skip }.count
    NavigationStack {
      List {
        Section {
          Text(rows.count == 1 ? "Add \(rows[0].name) to Kinwall?" : "Add these \(rows.count) contacts to Kinwall?").font(.title3.bold())
          if rows.contains(where: { !$0.duplicateIds.isEmpty }) {
            Text("Possible duplicates have the same phone, email or name as a saved contact.").font(.subheadline).foregroundStyle(.secondary)
          }
        }
        if let result { Section { Text(result).font(.headline) } }
        ForEach($rows) { $row in
          Section {
            VStack(alignment: .leading, spacing: 4) {
              HStack(alignment: .firstTextBaseline) {
                Text(row.name).font(.headline)
                Spacer()
                if row.duplicateIds.isEmpty { Label("New", systemImage: "plus.circle").font(.caption.bold()).foregroundStyle(.green) }
                else { Label("Possible duplicate", systemImage: "exclamationmark.triangle.fill").font(.caption.bold()).foregroundStyle(.orange) }
              }
              if !row.detail.isEmpty { Text(row.detail).font(.subheadline).foregroundStyle(.secondary) }
            }
            Picker("Action", selection: $row.decision) {
              ForEach(row.duplicateIds.isEmpty ? [.add, .skip] : [.skip, .merge, .keep] as [ContactImport.Decision], id: \.self) { Text($0.label).tag($0) }
            }
            .disabled(saving || result != nil)
          }
        }
      }
      .navigationTitle("Add to Kinwall")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if result == nil { ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onDone) } }
        ToolbarItem(placement: .confirmationAction) {
          if saving { ProgressView() }
          else if result == nil { Button("Import \(count)") { Task { await importIt() } }.bold().disabled(count == 0) }
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
