import Foundation

/// Pairs this device with a household: ask the server for a code, show it, and wait while an
/// admin approves it in Kinwall (Settings → Access → Displays → Pair a display). The approved
/// device gets its own display-scope key.
public struct Pairing: Sendable {
    public let client: KinwallClient
    public let pollEvery: Duration

    public init(baseURL: URL, session: URLSession = .shared, pollEvery: Duration = .seconds(2)) {
        client = KinwallClient(baseURL: baseURL, session: session)
        self.pollEvery = pollEvery
    }

    /// Step 1: get the 6-digit code to show.
    public func start() async throws -> PairStart { try await client.startPairing() }

    /// Step 2: poll until approved, then return the connection to save. Throws the server's
    /// 404 APIError once the code expires (10 minutes), and CancellationError if the task is
    /// cancelled (the person closed the screen).
    public func waitForApproval(_ start: PairStart) async throws -> Connection {
        while true {
            try Task.checkCancellation()
            if case .approved(let key) = try await client.pollPairing(start) {
                return Connection(baseURL: client.baseURL, key: key)
            }
            try await Task.sleep(for: pollEvery)
        }
    }
}
