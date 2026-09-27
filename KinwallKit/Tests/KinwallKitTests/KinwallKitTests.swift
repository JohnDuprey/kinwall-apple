import Foundation
import Testing
@testable import KinwallKit

// MARK: - A fake network for unit tests

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var seen: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var req = request
        if req.httpBody == nil, let stream = req.httpBodyStream { // URLSession moves bodies into a stream
            stream.open(); var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            stream.close(); req.httpBody = data
        }
        Self.seen.append(req)
        let (status, body) = Self.handler?(req) ?? (500, Data())
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func stubSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    return URLSession(configuration: config)
}

@Suite(.serialized) struct ClientTests {
    let base = URL(string: "https://ourfamily.kinwall.family/")!

    @Test func sendsTheKeyAndDecodesChores() async throws {
        StubProtocol.seen = []
        StubProtocol.handler = { _ in (200, Data(#"[{"id":"c1","title":"Water plants","emoji":null,"memberId":null,"points":5,"rrule":null,"dueDate":"2026-09-26","dueTime":null,"active":true,"sort":0,"listId":null,"completed":true,"completedAt":"x","completedBy":"m2","checklist":null}]"#.utf8)) }
        let chores = try await KinwallClient(baseURL: base, key: "kw_test", session: stubSession()).chores(on: "2026-09-26")
        #expect(chores.first?.isAnyone == true)
        #expect(chores.first?.completedBy == "m2")
        let req = try #require(StubProtocol.seen.first)
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer kw_test")
        #expect(req.url?.absoluteString == "https://ourfamily.kinwall.family/api/chores/day?date=2026-09-26")
    }

    @Test func completingAnAnyoneChoreSendsWhoDidIt() async throws {
        StubProtocol.seen = []
        StubProtocol.handler = { _ in (200, Data("{}".utf8)) }
        try await KinwallClient(baseURL: base, key: "k", session: stubSession()).complete(chore: "c1", on: "2026-09-26", by: "m2")
        let req = try #require(StubProtocol.seen.first)
        #expect(req.httpMethod == "POST")
        let body = try JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: String]
        #expect(body == ["date": "2026-09-26", "memberId": "m2"])
    }

    @Test func serverErrorsCarryTheirMessage() async throws {
        StubProtocol.handler = { _ in (409, Data(#"{"error":"Checklist not finished (2 left)","remaining":2}"#.utf8)) }
        await #expect(throws: APIError(status: 409, message: "Checklist not finished (2 left)")) {
            try await KinwallClient(baseURL: base, key: "k", session: stubSession()).complete(chore: "c1", on: "2026-09-26")
        }
    }

    @Test func pairingPollsUntilApproved() async throws {
        var polls = 0
        StubProtocol.handler = { req in
            if req.url?.path == "/api/pair" { return (201, Data(#"{"pairingId":"p1","code":"123456","pollToken":"t","expiresAt":"2026-09-26T20:00:00Z"}"#.utf8)) }
            polls += 1
            return polls < 3 ? (200, Data(#"{"status":"pending"}"#.utf8)) : (200, Data(#"{"status":"approved","key":"kw_display"}"#.utf8))
        }
        let pairing = Pairing(baseURL: base, session: stubSession(), pollEvery: .milliseconds(10))
        let start = try await pairing.start()
        #expect(start.code == "123456")
        let connection = try await pairing.waitForApproval(start)
        #expect(connection == Connection(baseURL: base, key: "kw_display"))
        #expect(polls == 3)
    }
}

@Test func householdDateUsesTheHouseholdTimezone() {
    // 2026-09-27 02:30 UTC is still the 26th in New York.
    let instant = ISO8601DateFormatter().date(from: "2026-09-27T02:30:00Z")!
    #expect(HouseholdDate.key(for: instant, timezone: "America/New_York") == "2026-09-26")
    #expect(HouseholdDate.key(for: instant, timezone: "Europe/Berlin") == "2026-09-27")
}

@Test func memoryStoreRoundTrips() throws {
    let store = MemoryConnectionStore()
    let c = Connection(baseURL: URL(string: "http://localhost:8080")!, key: "k")
    try store.save(c)
    #expect(try store.load() == c)
    try store.clear()
    #expect(try store.load() == nil)
}

// MARK: - OAuth

@Test func pkceMatchesTheRFC7636Example() {
    let p = OAuth.PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
    #expect(p.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
}

@Test func theCallbackMustCarryOurStateAndACode() throws {
    #expect(try OAuthClient.code(from: URL(string: "family.kinwall.app:/oauth?code=abc&state=s1&iss=x")!, state: "s1") == "abc")
    #expect(throws: OAuthError.self) { try OAuthClient.code(from: URL(string: "family.kinwall.app:/oauth?code=abc&state=other")!, state: "s1") }
    #expect(throws: OAuthError(code: "access_denied", message: "Sign-in was declined.")) {
        try OAuthClient.code(from: URL(string: "family.kinwall.app:/oauth?error=access_denied&state=s1")!, state: "s1")
    }
}

@Test func authorizeURLAsksForAdminWithS256() {
    let url = OAuthClient(baseURL: URL(string: "https://ourfamily.kinwall.family/")!).authorizeURL(clientId: "c1", pkce: OAuth.PKCE(verifier: "v"), state: "s")
    let q = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    #expect(url.path() == "/oauth/authorize")
    #expect(q["redirect_uri"] == "family.kinwall.app:/oauth")
    #expect(q["code_challenge_method"] == "S256")
    #expect(q["scope"] == "kinwall:admin")
}

@Test func tokensRefreshFiveMinutesEarly() {
    let t = OAuth.Tokens(baseURL: URL(string: "https://x")!, clientId: "c", accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSinceNow: 240), scope: "kinwall:display")
    #expect(t.needsRefresh())
    #expect(!OAuth.Tokens(baseURL: t.baseURL, clientId: "c", accessToken: "a", refreshToken: "r", expiresAt: Date(timeIntervalSinceNow: 3600), scope: "").needsRefresh())
}

@Test func nowAndNextPicksTheRunningAndTheNextTimedEvent() throws {
    let json = #"""
{"today":"2026-09-26","events":[
      {"id":"a","title":"Reading","start":"2026-09-26T19:20:00.000Z","end":"2026-09-26T20:05:00.000Z","allDay":false,"memberIds":[],"color":null,"location":null,"leaveAt":null,"date":"2026-09-26"},
      {"id":"b","title":"Soccer","start":"2026-09-26T20:00:00Z","end":"2026-09-26T21:30:00Z","allDay":false,"memberIds":["m2"],"color":"#7ED9A6","location":"Park field","leaveAt":"2026-09-26T19:40:00Z","date":"2026-09-26"},
      {"id":"c","title":"Holiday","start":"2026-09-26","end":"2026-09-27","allDay":true,"memberIds":[],"color":null,"location":null,"leaveAt":null,"date":"2026-09-26"}],
      "items":[],"chores":[{"memberId":null,"name":null,"avatar":null,"color":null,"remaining":1,"total":2}],"birthdays":[],"to":"2026-09-28","generatedAt":"x","weather":null}
"""#
    let board = try JSONDecoder().decode(Board.self, from: Data(json.utf8))
    let at = ISO8601DateFormatter().date(from: "2026-09-26T19:40:00Z")!
    let (now, next) = board.nowAndNext(at: at)
    #expect(now?.id == "a")
    #expect(next?.id == "b")
    #expect(next?.leaveDate == ISO8601DateFormatter().date(from: "2026-09-26T19:40:00Z"))
}
