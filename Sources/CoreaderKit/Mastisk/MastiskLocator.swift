import Foundation

/// Finds a Mastisk the reader's notes can show up in: one on this Mac, or one on
/// another of the person's machines reached over Tailscale. Network and process access
/// are passed in, so this stays testable and platform-neutral.
public struct MastiskLocator: Sendable {
    /// A reachable Mastisk and what it says about the Coreader connector.
    public struct Found: Sendable, Equatable {
        public var baseURL: URL
        public var isLocal: Bool
        /// nil when this Mastisk has no Coreader connector (it answered 404).
        public var connector: Connector?

        /// Lower is better: connector on, connector off, no connector.
        var rank: Int { connector.map { $0.enabled ? 0 : 1 } ?? 2 }
    }

    public struct Connector: Sendable, Equatable {
        public var enabled: Bool
        public var libraryRoot: String
        public var books: Int
    }

    /// GET a URL; returns status and body, or nil when unreachable.
    public typealias Fetch = @Sendable (URL) async -> (status: Int, body: Data)?

    public static let localURL = URL(string: "http://127.0.0.1:5555")!
    /// Ports a Mastisk is usually published on through Tailscale Serve.
    static let tailnetPorts = [8443, 443]

    var fetch: Fetch
    var local: URL

    public init(local: URL = MastiskLocator.localURL, fetch: @escaping Fetch) {
        self.local = local
        self.fetch = fetch
    }

    /// Local first, then the address remembered from last time, then tailnet peers.
    public func locate(remembered: URL?, tailscaleStatus: Data?) async -> Found? {
        if let found = await probe(local, isLocal: true) { return found }
        if let remembered, let found = await probe(remembered, isLocal: false) { return found }
        let candidates = Self.candidates(fromTailscaleStatus: tailscaleStatus)
        // Every candidate is heard out (each probe is bounded by the fetch timeout): the
        // first to answer may be a Mastisk without the connector while the right one is
        // a moment slower. Ties go to the lower address so the choice is stable.
        let found = await withTaskGroup(of: Found?.self) { group -> [Found] in
            for url in candidates { group.addTask { await probe(url, isLocal: false) } }
            var all: [Found] = []
            for await found in group { if let found { all.append(found) } }
            return all
        }
        return found.sorted { ($0.rank, $0.baseURL.absoluteString) < ($1.rank, $1.baseURL.absoluteString) }.first
    }

    /// A server counts as Mastisk only if its health answer has Mastisk's shape; other
    /// services on the tailnet answer the same path with something else.
    func probe(_ base: URL, isLocal: Bool) async -> Found? {
        guard let health = await fetch(base.appendingPathComponent("api/health")), health.status == 200,
              let json = try? JSONSerialization.jsonObject(with: health.body) as? [String: Any],
              json["ok"] as? Bool == true, json.keys.contains("public_url") else { return nil }
        var found = Found(baseURL: base, isLocal: isLocal, connector: nil)
        if let answer = await fetch(base.appendingPathComponent("api/coreader")), answer.status == 200,
           let state = try? JSONSerialization.jsonObject(with: answer.body) as? [String: Any],
           let enabled = state["enabled"] as? Bool {
            found.connector = Connector(enabled: enabled, libraryRoot: state["library_root"] as? String ?? "", books: state["books"] as? Int ?? 0)
        }
        return found
    }

    /// Online peers from `tailscale status --json`, as https addresses to try. Phones and
    /// TVs are skipped: they cannot host Mastisk.
    public static func candidates(fromTailscaleStatus data: Data?) -> [URL] {
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let peers = json["Peer"] as? [String: Any] else { return [] }
        var urls: [URL] = []
        for case let peer as [String: Any] in peers.values {
            guard peer["Online"] as? Bool == true, let os = peer["OS"] as? String, ["macOS", "linux", "windows"].contains(os),
                  let dns = (peer["DNSName"] as? String)?.trimmingCharacters(in: CharacterSet(charactersIn: ".")), !dns.isEmpty,
                  dns.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil else { continue }
            for port in tailnetPorts {
                if let url = URL(string: port == 443 ? "https://\(dns)" : "https://\(dns):\(port)") { urls.append(url) }
            }
        }
        return urls.sorted { $0.absoluteString < $1.absoluteString }
    }

    /// The part of a path below iCloud Drive, lowercased (iCloud folders are
    /// case-insensitive), or nil when the folder is not in iCloud Drive.
    public static func iCloudRelativePath(_ path: String) -> String? {
        guard let range = path.range(of: "/Mobile Documents/com~apple~CloudDocs/") else { return nil }
        return path[range.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
    }

    /// Whether two paths on this Mac name the same folder (the volume is case-insensitive).
    public static func sameFolder(_ a: String, _ b: String) -> Bool {
        func normal(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path.lowercased() }
        return normal(a) == normal(b)
    }

    /// Another machine's Mastisk reads its own copy of the library, so it sees these
    /// notes only if both sides use the same folder in iCloud Drive.
    public static func sharesLibrary(local: String, remote: String) -> Bool {
        guard let a = iCloudRelativePath(local), let b = iCloudRelativePath(remote) else { return false }
        return a == b
    }
}
