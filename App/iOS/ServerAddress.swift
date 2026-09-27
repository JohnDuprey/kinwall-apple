import Foundation

/// The household's Kinwall address, kept in UserDefaults under the same key the Settings.bundle
/// field writes, so it can be changed from the iOS Settings app too.
enum ServerAddress {
    static let defaultsKey = "serverURL"

    static var current: URL? { UserDefaults.standard.string(forKey: defaultsKey).flatMap(normalize) }
    static func save(_ url: URL) { UserDefaults.standard.set(url.absoluteString, forKey: defaultsKey) }
    static func clear() { UserDefaults.standard.removeObject(forKey: defaultsKey) }

    /// "ourfamily" → https://ourfamily.kinwall.family, "kinwall.local:8080" → http://kinwall.local:8080,
    /// "http://192.168.1.20:8080" stays as typed. Returns nil for anything that isn't a web address.
    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return nil }
        if !s.contains(".") && !s.contains(":") && !s.contains("/") { s = "\(s).kinwall.family" } // hosted family name
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            // A home server by IP, localhost or a .local name rarely has https; everything else does.
            let host = s.split(separator: "/").first.map { $0.split(separator: ":").first.map(String.init) ?? "" } ?? ""
            let local = host == "localhost" || host.hasSuffix(".local") || host.allSatisfy { $0.isNumber || $0 == "." }
            s = (local ? "http://" : "https://") + s
        }
        guard var c = URLComponents(string: s), let host = c.host, !host.isEmpty else { return nil }
        c.path = c.path.isEmpty ? "/" : c.path
        c.query = nil; c.fragment = nil
        return c.url
    }
}
