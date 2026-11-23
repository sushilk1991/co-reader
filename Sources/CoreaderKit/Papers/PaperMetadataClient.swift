import Foundation

public struct PaperMetadata: Sendable, Equatable, Codable {
    public var title: String
    public var authors: [String]
    public var abstract: String?
    public var year: Int?
    public var venue: String?
    public var doi: String?
    public var arxivID: String?
    public var pdfURL: URL?
    public var landingURL: URL?

    public init(
        title: String, authors: [String] = [], abstract: String? = nil, year: Int? = nil, venue: String? = nil,
        doi: String? = nil, arxivID: String? = nil, pdfURL: URL? = nil, landingURL: URL? = nil
    ) {
        self.title = title
        self.authors = authors
        self.abstract = abstract
        self.year = year
        self.venue = venue
        self.doi = doi
        self.arxivID = arxivID
        self.pdfURL = pdfURL
        self.landingURL = landingURL
    }
}

public enum PaperLookupError: Error, Sendable, Equatable, LocalizedError {
    /// Not an arXiv id, arXiv link or DOI.
    case unrecognizedInput(String)
    case notFound
    /// The service asked us to slow down (HTTP 429).
    case rateLimited(retryAfter: TimeInterval?)
    case http(status: Int)
    case malformedResponse
    /// No open PDF is known for this paper.
    case noPDFAvailable
    /// The download was something other than a PDF (usually a paywall page).
    case notAPDF

    public var errorDescription: String? {
        switch self {
        case .unrecognizedInput: "That is not an arXiv link, arXiv id or DOI."
        case .notFound: "No paper was found."
        case .rateLimited: "The paper service is busy. Try again in a moment."
        case .http(let status): "The paper service answered with an error (\(status))."
        case .malformedResponse: "The paper service sent a reply that could not be read."
        case .noPDFAvailable: "No freely downloadable PDF is known for this paper."
        case .notAPDF: "The download was not a PDF, probably because the paper is behind a paywall."
        }
    }
}

/// Looks papers up by identifier or title. Three public services, none needing a key:
///
/// - **arXiv** (`export.arxiv.org/api/query`), Atom XML. arXiv asks for no more than one
///   request every three seconds.
/// - **Crossref** (`api.crossref.org/works`), JSON, for DOIs. Anonymous use is the
///   "public pool": about 5 requests a second, 1 at a time; answers 429 beyond that.
/// - **Semantic Scholar** (`api.semanticscholar.org/graph/v1/paper/search/match`) for
///   title search, because unlike Crossref it knows arXiv-only papers and usually has
///   the abstract. Without a key all anonymous callers share one pool, so 429s happen;
///   `search(title:)` then falls back to Crossref's bibliographic search, and asks
///   arXiv's title search for the abstract when the answer so far has none.
///
/// Requests to one host are spaced by `PaperRequestPacer`, so a burst of citation hovers
/// cannot trip those limits.
public struct PaperMetadataClient: Sendable {
    public static let userAgent = "Coreader/1.0"

    private let http: any HTTPFetching
    private let pacer: PaperRequestPacer?

    public init(http: any HTTPFetching = URLSessionHTTP()) {
        self.init(http: http, pacer: .shared)
    }

    /// Tests pass `pacer: nil` so fixtures answer without waiting.
    init(http: any HTTPFetching, pacer: PaperRequestPacer?) {
        self.http = http
        self.pacer = pacer
    }

    // MARK: Lookups

    public func lookup(arxivID: String) async throws -> PaperMetadata {
        guard let id = PaperIdentifier.arxivID(exactly: arxivID.trimmingCharacters(in: .whitespaces)) else {
            throw PaperLookupError.unrecognizedInput(arxivID)
        }
        var components = URLComponents(string: "https://export.arxiv.org/api/query")!
        components.queryItems = [URLQueryItem(name: "id_list", value: id), URLQueryItem(name: "max_results", value: "1")]
        let data = try await get(components.url!, accept: "application/atom+xml")
        guard let paper = ArxivFeedParser.parse(data).first else { throw PaperLookupError.notFound }
        return paper
    }

    public func lookup(doi: String) async throws -> PaperMetadata {
        guard let cleaned = PaperIdentifier.doi(in: doi) else { throw PaperLookupError.unrecognizedInput(doi) }
        if case .arxiv(let id) = PaperIdentifier.identifier(forDOI: cleaned) {
            return try await lookup(arxivID: id)
        }
        // A DOI may contain almost anything; only unreserved characters and "/" go unescaped.
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/")
        let path = cleaned.addingPercentEncoding(withAllowedCharacters: allowed) ?? cleaned
        guard let url = URL(string: "https://api.crossref.org/works/\(path)") else {
            throw PaperLookupError.unrecognizedInput(doi)
        }
        let data = try await get(url, accept: "application/json")
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any],
              let paper = Self.paper(fromCrossref: message)
        else { throw PaperLookupError.malformedResponse }
        return paper
    }

    /// The paper whose title matches, or nil when nothing is close enough. A wrong paper
    /// shown with confidence is worse than none, so a candidate must reach
    /// `PaperTitleSimilarity.acceptThreshold`.
    ///
    /// Semantic Scholar is asked first, Crossref when it is rate limited or has nothing,
    /// and arXiv's own title search when the result so far is missing or has no abstract
    /// (Crossref rarely has abstracts and does not know arXiv-only preprints). Throws only
    /// when every service that was asked failed.
    public func search(title: String) async throws -> PaperMetadata? {
        let query = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard query.count >= 6 else { return nil }

        var failure: Error?
        var answered = false
        func attempt(_ search: () async throws -> PaperMetadata?) async throws -> PaperMetadata? {
            do {
                let paper = try await search()
                answered = true
                return paper
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failure = error
                return nil
            }
        }

        var paper = try await attempt { try await searchSemanticScholar(query) }
        if paper == nil {
            paper = try await attempt { try await searchCrossref(query) }
        }
        if paper?.abstract == nil {
            let preprint: PaperMetadata?
            if let id = paper?.arxivID {
                preprint = try await attempt { try await lookup(arxivID: id) }
            } else {
                preprint = try await attempt { try await searchArxiv(query) }
            }
            // A title alone does not identify a paper: famous titles are reused (a 2021
            // tutorial is also called "Long Short-Term Memory"). A preprint found by title
            // may only fill in a record whose authors it shares.
            if let preprint, paper == nil || paper?.arxivID != nil || Self.shareAnAuthor(paper?.authors ?? [], preprint.authors) {
                var combined = paper ?? preprint
                combined.abstract = preprint.abstract
                combined.arxivID = combined.arxivID ?? preprint.arxivID
                // The arXiv copy is the one anybody can download.
                combined.pdfURL = preprint.pdfURL ?? combined.pdfURL
                paper = combined
            }
        }
        if paper == nil, !answered, let failure { throw failure }
        return paper
    }

    /// True when the two author lists have a family name in common. Names are compared
    /// by their last word, lowercased and without diacritics ("S. Hochreiter" matches
    /// "Sepp Hochreiter").
    static func shareAnAuthor(_ a: [String], _ b: [String]) -> Bool {
        func families(_ names: [String]) -> Set<String> {
            Set(names.compactMap { name in
                name.split(whereSeparator: { $0 == " " || $0 == "," }).last
                    .map { String($0).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased() }
            }.filter { $0.count > 1 })
        }
        return !families(a).isDisjoint(with: families(b))
    }

    /// Accepts an arXiv abs/pdf link, a bare arXiv id, a DOI or a doi.org link.
    public func resolve(_ input: String) async throws -> PaperMetadata {
        switch PaperIdentifier.parse(input) {
        case .arxiv(let id): return try await lookup(arxivID: id)
        case .doi(let doi): return try await lookup(doi: doi)
        case nil: throw PaperLookupError.unrecognizedInput(input)
        }
    }

    /// Downloads the paper's PDF into `directory` and returns the file.
    public func downloadPDF(_ meta: PaperMetadata, to directory: URL) async throws -> URL {
        let source: URL
        if let url = meta.pdfURL {
            source = url
        } else if let id = meta.arxivID, let url = URL(string: "https://arxiv.org/pdf/\(id)") {
            source = url
        } else {
            throw PaperLookupError.noPDFAvailable
        }
        let data = try await get(source, accept: "application/pdf")
        // Publishers answer 200 with an HTML login page; only "%PDF" is a PDF.
        guard data.prefix(1024).range(of: Data("%PDF".utf8)) != nil else { throw PaperLookupError.notAPDF }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(Self.fileName(for: meta))
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func fileName(for meta: PaperMetadata) -> String {
        if let id = meta.arxivID { return id.replacingOccurrences(of: "/", with: "_") + ".pdf" }
        let slug = meta.title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(8)
            .joined(separator: "-")
        return (slug.isEmpty ? "paper" : String(slug.prefix(80))) + ".pdf"
    }

    // MARK: Title search

    private func searchSemanticScholar(_ title: String) async throws -> PaperMetadata? {
        var components = URLComponents(string: "https://api.semanticscholar.org/graph/v1/paper/search/match")!
        components.queryItems = [
            URLQueryItem(name: "query", value: title),
            URLQueryItem(name: "fields", value: "title,authors,abstract,year,venue,externalIds,openAccessPdf,url"),
        ]
        let data: Data
        do {
            data = try await get(components.url!, accept: "application/json")
        } catch PaperLookupError.notFound {
            return nil   // 404 is this endpoint's way of saying "no title matches"
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["data"] as? [[String: Any]]
        else { throw PaperLookupError.malformedResponse }
        return Self.bestMatch(for: title, among: items.compactMap(Self.paper(fromSemanticScholar:)))
    }

    private func searchCrossref(_ title: String) async throws -> PaperMetadata? {
        var components = URLComponents(string: "https://api.crossref.org/works")!
        components.queryItems = [
            URLQueryItem(name: "query.bibliographic", value: title),
            URLQueryItem(name: "rows", value: "5"),
            URLQueryItem(name: "select", value: "DOI,title,author,issued,container-title,abstract,URL,link"),
        ]
        let data = try await get(components.url!, accept: "application/json")
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = root["message"] as? [String: Any],
              let items = message["items"] as? [[String: Any]]
        else { throw PaperLookupError.malformedResponse }
        return Self.bestMatch(for: title, among: items.compactMap(Self.paper(fromCrossref:)))
    }

    private func searchArxiv(_ title: String) async throws -> PaperMetadata? {
        // Inside ti:"..." a quote or a bracket would end or alter the query.
        let phrase = PaperTitleSimilarity.normalize(title)
        guard !phrase.isEmpty else { return nil }
        var components = URLComponents(string: "https://export.arxiv.org/api/query")!
        components.queryItems = [
            URLQueryItem(name: "search_query", value: "ti:\"\(phrase)\""),
            URLQueryItem(name: "max_results", value: "3"),
        ]
        let data = try await get(components.url!, accept: "application/atom+xml")
        return Self.bestMatch(for: title, among: ArxivFeedParser.parse(data))
    }

    static func bestMatch(for title: String, among candidates: [PaperMetadata]) -> PaperMetadata? {
        let scored = candidates.map { (paper: $0, score: PaperTitleSimilarity.score(title, $0.title)) }
        guard let best = scored.max(by: { $0.score < $1.score }), best.score >= PaperTitleSimilarity.acceptThreshold else {
            return nil
        }
        return best.paper
    }

    // MARK: Transport

    private func get(_ url: URL, accept: String) async throws -> Data {
        if let pacer, let host = url.host { try await pacer.wait(for: host) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, response) = try await http.data(for: request)
        switch response.statusCode {
        case 200..<300: return data
        case 404: throw PaperLookupError.notFound
        case 429:
            let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw PaperLookupError.rateLimited(retryAfter: retry)
        default: throw PaperLookupError.http(status: response.statusCode)
        }
    }

    // MARK: Decoding

    static func paper(fromCrossref item: [String: Any]) -> PaperMetadata? {
        guard let title = (item["title"] as? [String])?.first.map(clean), !title.isEmpty else { return nil }
        let authors = (item["author"] as? [[String: Any]] ?? []).compactMap { author -> String? in
            let given = author["given"] as? String ?? ""
            let family = author["family"] as? String ?? ""
            let name = clean("\(given) \(family)")
            return name.isEmpty ? (author["name"] as? String).map(clean) : name
        }
        // "issued" is the earliest of print and online publication.
        let year = ["issued", "published", "published-print", "published-online", "created"].lazy.compactMap { key -> Int? in
            let parts = (item[key] as? [String: Any])?["date-parts"] as? [[Any]]
            return parts?.first?.first as? Int
        }.first
        let doi = (item["DOI"] as? String)?.lowercased()
        let pdf = (item["link"] as? [[String: Any]] ?? []).first { ($0["content-type"] as? String) == "application/pdf" }
        return PaperMetadata(
            title: title,
            authors: authors,
            abstract: (item["abstract"] as? String).map(stripMarkup).flatMap { $0.isEmpty ? nil : $0 },
            year: year,
            venue: (item["container-title"] as? [String])?.first.map(clean).flatMap { $0.isEmpty ? nil : $0 },
            doi: doi,
            arxivID: nil,
            pdfURL: (pdf?["URL"] as? String).flatMap(URL.init(string:)),
            landingURL: doi.flatMap { URL(string: "https://doi.org/\($0)") } ?? (item["URL"] as? String).flatMap(URL.init(string:))
        )
    }

    static func paper(fromSemanticScholar item: [String: Any]) -> PaperMetadata? {
        guard let title = (item["title"] as? String).map(clean), !title.isEmpty else { return nil }
        let ids = item["externalIds"] as? [String: Any] ?? [:]
        let arxiv = (ids["ArXiv"] as? String).flatMap(PaperIdentifier.arxivID(exactly:))
        var doi = (ids["DOI"] as? String)?.lowercased()
        // The arXiv DOI adds nothing once the arXiv id is known, and Crossref cannot resolve it.
        if let found = doi, case .arxiv = PaperIdentifier.identifier(forDOI: found) { doi = nil }
        let openPDF = ((item["openAccessPdf"] as? [String: Any])?["url"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        return PaperMetadata(
            title: title,
            authors: (item["authors"] as? [[String: Any]] ?? []).compactMap { ($0["name"] as? String).map(clean) },
            abstract: (item["abstract"] as? String).map(clean).flatMap { $0.isEmpty ? nil : $0 },
            year: item["year"] as? Int,
            venue: (item["venue"] as? String).map(clean).flatMap { $0.isEmpty ? nil : $0 },
            doi: doi,
            arxivID: arxiv,
            pdfURL: openPDF ?? arxiv.flatMap { URL(string: "https://arxiv.org/pdf/\($0)") },
            landingURL: arxiv.flatMap { URL(string: "https://arxiv.org/abs/\($0)") }
                ?? doi.flatMap { URL(string: "https://doi.org/\($0)") }
                ?? (item["url"] as? String).flatMap(URL.init(string:))
        )
    }

    static func clean(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Crossref abstracts are JATS XML fragments (`<jats:p>…`), sometimes with a leading
    /// "Abstract" heading.
    static func stripMarkup(_ text: String) -> String {
        var plain = text.replacingOccurrences(of: #"<jats:title>[^<]*</jats:title>"#, with: " ", options: .regularExpression)
        plain = plain.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        for (entity, character) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'")] {
            plain = plain.replacingOccurrences(of: entity, with: character)
        }
        plain = clean(plain)
        if plain.lowercased().hasPrefix("abstract ") { plain = String(plain.dropFirst(9)) }
        return plain
    }
}

/// Keeps a minimum gap between requests to one host, across every client in the process.
actor PaperRequestPacer {
    static let shared = PaperRequestPacer(intervals: [
        "export.arxiv.org": 3,
        "api.semanticscholar.org": 1.1,
        "api.crossref.org": 0.25,
    ])

    private let intervals: [String: TimeInterval]
    private var nextAllowed: [String: Date] = [:]

    init(intervals: [String: TimeInterval]) {
        self.intervals = intervals
    }

    func wait(for host: String) async throws {
        guard let interval = intervals[host] else { return }
        let now = Date()
        let slot = max(nextAllowed[host] ?? now, now)
        // Reserve the slot before sleeping, so callers queued behind this one line up after it.
        nextAllowed[host] = slot.addingTimeInterval(interval)
        let delay = slot.timeIntervalSince(now)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
    }
}

/// How alike two paper titles are, ignoring case, punctuation and accents.
public enum PaperTitleSimilarity {
    /// Below this, a search result is treated as a different paper.
    public static let acceptThreshold = 0.86

    /// 0...1. Edit-distance ratio of the normalised titles, with credit when one is the
    /// other plus a subtitle (references often drop subtitles).
    public static func score(_ a: String, _ b: String) -> Double {
        let x = normalize(a), y = normalize(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        if x == y { return 1 }
        let (short, long) = x.count <= y.count ? (x, y) : (y, x)
        var best = 1 - Double(editDistance(Array(x.unicodeScalars), Array(y.unicodeScalars))) / Double(long.count)
        if short.count >= 18, short.split(separator: " ").count >= 3, long.hasPrefix(short + " ") {
            best = max(best, 0.9)
        }
        return best
    }

    static func normalize(_ title: String) -> String {
        title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func editDistance(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(substitution, previous[j] + 1, current[j - 1] + 1)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

/// Reads arXiv's Atom feed. `XMLParser` is event-based, so this collects text per element.
final class ArxivFeedParser: NSObject, XMLParserDelegate {
    private var papers: [PaperMetadata] = []
    private var inEntry = false
    private var text = ""
    private var entry = Entry()

    private struct Entry {
        var id = "", title = "", summary = "", published = ""
        var authors: [String] = []
        var doi: String?, journal: String?
        var pdf: URL?, landing: URL?
    }

    static func parse(_ data: Data) -> [PaperMetadata] {
        let delegate = ArxivFeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.papers
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        text = ""
        if name == "entry" {
            inEntry = true
            entry = Entry()
        } else if inEntry, name == "link", let href = attributes["href"], let url = URL(string: href) {
            if attributes["title"] == "pdf" || attributes["type"] == "application/pdf" {
                entry.pdf = url
            } else if attributes["rel"] == "alternate" {
                entry.landing = url
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard inEntry else { return }
        let value = PaperMetadataClient.clean(text)
        switch name {
        case "id": entry.id = value
        case "title": entry.title = value
        case "summary": entry.summary = value
        case "published": entry.published = value
        case "name": if !value.isEmpty { entry.authors.append(value) }
        case "arxiv:doi": entry.doi = value.lowercased()
        case "arxiv:journal_ref": entry.journal = value
        case "entry":
            inEntry = false
            // An unknown id comes back as a feed with no entry, or an entry titled "Error".
            guard !entry.title.isEmpty, entry.title != "Error", let idPart = entry.id.components(separatedBy: "/abs/").last,
                  let id = PaperIdentifier.arxivID(exactly: idPart)
            else { return }
            papers.append(PaperMetadata(
                title: entry.title,
                authors: entry.authors,
                abstract: entry.summary.isEmpty ? nil : entry.summary,
                year: Int(entry.published.prefix(4)),
                venue: entry.journal ?? "arXiv",
                doi: entry.doi,
                arxivID: id,
                // Versionless links, so the app always fetches the latest revision.
                pdfURL: URL(string: "https://arxiv.org/pdf/\(id)"),
                landingURL: URL(string: "https://arxiv.org/abs/\(id)")
            ))
        default: break
        }
        text = ""
    }
}
