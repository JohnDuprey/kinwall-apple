import Foundation
import Testing
@testable import KinwallKit

// Runs against a real Kinwall server when KINWALL_TEST_URL and KINWALL_TEST_ADMIN_KEY are set
// (use a throwaway local server: it creates a member, a chore and a list). Skipped otherwise.
//   cd kinwall/server && DATA_DIR=$(mktemp -d) ADMIN_API_KEY=… PORT=8177 npm start
//   KINWALL_TEST_URL=http://127.0.0.1:8177 KINWALL_TEST_ADMIN_KEY=… swift test
private let env = ProcessInfo.processInfo.environment
private let liveURL = env["KINWALL_TEST_URL"].flatMap(URL.init(string:))
private let adminKey = env["KINWALL_TEST_ADMIN_KEY"]

@Test(.enabled(if: liveURL != nil && adminKey != nil))
func pairsThenUsesTheDisplayKeyLikeTheApp() async throws {
    let base = try #require(liveURL)
    let admin = KinwallClient(baseURL: base, key: adminKey)

    // Pairing: the app asks for a code, an admin approves it, the app receives its own key.
    let pairing = Pairing(baseURL: base, pollEvery: .milliseconds(200))
    let start = try await pairing.start()
    #expect(start.code.count == 6)
    struct Approve: Encodable { let code: String; let name: String }
    struct Approved: Decodable { let keyId: String }
    let _: Approved = try await admin.send("POST", "api/pair/approve", body: Approve(code: start.code, name: "KinwallKit test"))
    let connection = try await pairing.waitForApproval(start)
    let app = KinwallClient(connection)

    // Setup data an admin would have made.
    struct NewMember: Encodable { let name: String; let color: String; let avatar: String }
    struct NewChore: Encodable { let title: String; let points: Int; let dueDate: String }
    struct NewList: Encodable { let name: String; let kind: String }
    struct Created: Decodable { let id: String }
    let settings = try await app.settings()
    let today = HouseholdDate.key(timezone: settings.timezone)
    let maya: Created = try await admin.send("POST", "api/members", body: NewMember(name: "Maya", color: "#7ED9A6", avatar: "🦄"))
    let chore: Created = try await admin.send("POST", "api/chores", body: NewChore(title: "Water plants", points: 5, dueDate: today))
    let list: Created = try await admin.send("POST", "api/lists", body: NewList(name: "Groceries", kind: "shopping"))

    // Everything below uses the paired display key, as the app will.
    #expect(try await app.members().contains { $0.id == maya.id })
    let rev0 = try await app.rev()

    let anyone = try #require(try await app.chores(on: today).first { $0.id == chore.id })
    #expect(anyone.isAnyone && !anyone.completed)
    try await app.complete(chore: chore.id, on: today, by: maya.id)
    let done = try #require(try await app.chores(on: today).first { $0.id == chore.id })
    #expect(done.completed && done.completedBy == maya.id)
    #expect(try await app.members().first { $0.id == maya.id }?.pointsToday == 5)
    try await app.uncomplete(chore: chore.id, on: today)
    #expect(try await app.chores(on: today).first { $0.id == chore.id }?.completed == false)

    let added = try await app.addItems(["Milk", "Eggs"], to: list.id)
    #expect(added.map(\.title) == ["Milk", "Eggs"])
    try await app.setDone(true, item: added[0].id, in: list.id)
    let detail = try await app.list(list.id)
    #expect(detail.items.first { $0.id == added[0].id }?.done == true)
    #expect(try await app.lists().first { $0.id == list.id }?.openCount == 1)

    #expect(try await app.rev() > rev0)
}

@Test(.enabled(if: liveURL != nil && adminKey != nil))
func signsInWithOAuthLikeTheApp() async throws {
    let base = try #require(liveURL)
    let oauth = OAuthClient(baseURL: base)
    let clientId = try await oauth.register(name: "Kinwall for iPhone (test)")
    let pkce = OAuth.PKCE()
    let state = OAuth.randomURLSafe(8)

    // The Safari sheet's part, done here with the admin key: the consent screen approves.
    struct Approve: Encodable { let decision = "approve"; let client_id: String; let redirect_uri = OAuth.redirectURI; let code_challenge: String; let code_challenge_method = "S256"; let state: String; let scope = "display" }
    struct Approved: Decodable { let redirect: String }
    let approved: Approved = try await KinwallClient(baseURL: base, key: adminKey).send("POST", "api/authorizations/approve", body: Approve(client_id: clientId, code_challenge: pkce.challenge, state: state))
    let code = try OAuthClient.code(from: try #require(URL(string: approved.redirect)), state: state)

    var tokens = try await oauth.exchange(code: code, pkce: pkce, clientId: clientId)
    #expect(tokens.scope == "kinwall:display")
    _ = try await KinwallClient(baseURL: base, key: tokens.accessToken).settings()

    let before = tokens
    tokens = try await oauth.refresh(tokens)
    #expect(tokens.refreshToken != before.refreshToken) // rotates
    await #expect(throws: OAuthError.self) { try await oauth.refresh(before) } // the old one is spent (and that ends the grant)

    await oauth.revoke(tokens)
    await #expect(throws: (any Error).self) { try await KinwallClient(baseURL: base, key: tokens.accessToken).settings() }
}

@Test(.enabled(if: liveURL != nil && adminKey != nil))
func widgetsGetTheirOwnKeyAndReadTheBoard() async throws {
    let base = try #require(liveURL)
    let app = KinwallClient(baseURL: base, key: adminKey)
    let device = try await app.createDeviceKey(name: "Widgets on iPhone (test)")
    let widgets = KinwallClient(baseURL: base, key: device.key)
    let board = try await widgets.board(days: 3)
    #expect(board.today.count == 10)
    _ = board.nowAndNext()
    try await widgets.revokeOwnKey()
    await #expect(throws: APIError.self) { try await widgets.board() }
}
