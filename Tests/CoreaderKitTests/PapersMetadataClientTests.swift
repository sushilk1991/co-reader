import Foundation
import Testing
@testable import CoreaderKit

/// Answers from fixtures and records what was asked.
private final class FakeHTTP: HTTPFetching, @unchecked Sendable {
    typealias Reply = (status: Int, body: Data, headers: [String: String])
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let handler: @Sendable (URL) -> Reply

    init(_ handler: @escaping @Sendable (URL) -> Reply) { self.handler = handler }

    var requests: [URLRequest] { lock.withLock { recorded } }
    var hosts: [String] { requests.compactMap { $0.url?.host } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { recorded.append(request) }
        let reply = handler(request.url!)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
        return (reply.body, response)
    }
}

private func ok(_ text: String) -> FakeHTTP.Reply { (200, Data(text.utf8), [:]) }
private func status(_ code: Int, _ headers: [String: String] = [:]) -> FakeHTTP.Reply { (code, Data("{}".utf8), headers) }

/// Routes by host the way the real services are laid out.
private func standardHTTP(semanticScholar: FakeHTTP.Reply? = nil) -> FakeHTTP {
    FakeHTTP { url in
        switch url.host {
        case "export.arxiv.org":
            let query = url.query?.removingPercentEncoding?.lowercased() ?? ""
            let hit = query.contains("1706.03762") || query.contains("ti:\"attention is all you need\"")
            return hit ? ok(PapersFixtures.arxivAttention) : ok(PapersFixtures.arxivEmpty)
        case "api.crossref.org":
            if url.path == "/works" { return ok(PapersFixtures.crossrefSearchResNet) }
            return url.path.hasSuffix("10.1038/nature14539") ? ok(PapersFixtures.crossrefDeepLearning) : status(404)
        case "api.semanticscholar.org":
            return semanticScholar ?? ok(PapersFixtures.semanticScholarAttention)
        case "arxiv.org":
            return (200, Data("%PDF-1.5 fake".utf8), [:])
        default:
            return status(500)
        }
    }
}

private func client(_ http: FakeHTTP) -> PaperMetadataClient { PaperMetadataClient(http: http, pacer: nil) }

@Test func papersArxivLookupReadsTheAtomFeed() async throws {
    let http = standardHTTP()
    let paper = try await client(http).lookup(arxivID: "1706.03762v5")
    #expect(paper.title == "Attention Is All You Need")
    #expect(paper.authors.count == 8)
    #expect(paper.authors.first == "Ashish Vaswani")
    #expect(paper.authors.last == "Illia Polosukhin")
    #expect(paper.abstract?.hasPrefix("The dominant sequence transduction models") == true)
    #expect(paper.abstract?.contains("\n") == false)
    #expect(paper.year == 2017)
    #expect(paper.arxivID == "1706.03762")
    #expect(paper.pdfURL?.absoluteString == "https://arxiv.org/pdf/1706.03762")
    #expect(paper.landingURL?.absoluteString == "https://arxiv.org/abs/1706.03762")

    let request = try #require(http.requests.first)
    #expect(request.url?.host == "export.arxiv.org")
    #expect(request.url?.query?.contains("id_list=1706.03762") == true)
    #expect(request.value(forHTTPHeaderField: "User-Agent") == "Coreader/1.0")
}

@Test func papersArxivLookupOfUnknownIDIsNotFound() async {
    await #expect(throws: PaperLookupError.notFound) { _ = try await client(standardHTTP()).lookup(arxivID: "9999.99999") }
    await #expect(throws: PaperLookupError.unrecognizedInput("not-an-id")) {
        _ = try await client(standardHTTP()).lookup(arxivID: "not-an-id")
    }
}

@Test func papersDOILookupReadsCrossref() async throws {
    let http = standardHTTP()
    let paper = try await client(http).lookup(doi: "https://doi.org/10.1038/NATURE14539.")
    #expect(paper.title == "Deep learning")
    #expect(paper.authors == ["Yann LeCun", "Yoshua Bengio", "Geoffrey Hinton"])
    #expect(paper.year == 2015)
    #expect(paper.venue == "Nature")
    #expect(paper.doi == "10.1038/nature14539")
    #expect(paper.pdfURL?.absoluteString == "http://www.nature.com/articles/nature14539.pdf")
    #expect(paper.landingURL?.absoluteString == "https://doi.org/10.1038/nature14539")
    #expect(http.requests.first?.url?.absoluteString == "https://api.crossref.org/works/10.1038/nature14539")

    await #expect(throws: PaperLookupError.notFound) { _ = try await client(http).lookup(doi: "10.9999/nope") }
}

@Test func papersArxivDOIsGoToArxivNotCrossref() async throws {
    let http = standardHTTP()
    let paper = try await client(http).lookup(doi: "10.48550/arXiv.1706.03762")
    #expect(paper.arxivID == "1706.03762")
    #expect(http.hosts == ["export.arxiv.org"])
}

@Test func papersResolveAcceptsLinksIDsAndDOIs() async throws {
    for input in [
        "https://arxiv.org/abs/1706.03762", "https://arxiv.org/pdf/1706.03762v7.pdf", "arxiv.org/abs/1706.03762v2",
        "arXiv:1706.03762", "1706.03762", " https://doi.org/10.48550/arXiv.1706.03762 ",
    ] {
        let paper = try await client(standardHTTP()).resolve(input)
        #expect(paper.title == "Attention Is All You Need", "input: \(input)")
    }
    for input in ["10.1038/nature14539", "doi:10.1038/nature14539", "https://dx.doi.org/10.1038/nature14539"] {
        let paper = try await client(standardHTTP()).resolve(input)
        #expect(paper.title == "Deep learning", "input: \(input)")
    }
    await #expect(throws: PaperLookupError.unrecognizedInput("https://example.com/paper")) {
        _ = try await client(standardHTTP()).resolve("https://example.com/paper")
    }
}

@Test func papersIdentifierParsing() {
    #expect(PaperIdentifier.parse("hep-th/9901001v2") == .arxiv("hep-th/9901001"))
    #expect(PaperIdentifier.parse("https://arxiv.org/abs/math.AG/0601001") == .arxiv("math.AG/0601001"))
    #expect(PaperIdentifier.parse("https://www.alphaxiv.org/abs/2301.01234") == .arxiv("2301.01234"))
    #expect(PaperIdentifier.parse("https://link.springer.com/article/10.1007/s11263-015-0816-y") == .doi("10.1007/s11263-015-0816-y"))
    #expect(PaperIdentifier.parse("10.1002/(SICI)1097-4571(199009)41:6<391::AID-ASI1>3.0.CO;2-9") != nil)
    #expect(PaperIdentifier.parse("") == nil)
    #expect(PaperIdentifier.parse("Attention is all you need") == nil)
    #expect(PaperIdentifier.parse("2017") == nil)
    #expect(PaperIdentifier.doi(in: "see doi:10.1145/3292500.3330701).") == "10.1145/3292500.3330701")
}

@Test func papersTitleSearchUsesSemanticScholar() async throws {
    let http = standardHTTP()
    let paper = try #require(try await client(http).search(title: "attention is all you need"))
    #expect(paper.title == "Attention is All you Need")
    #expect(paper.arxivID == "1706.03762")
    #expect(paper.doi == nil)   // only the arXiv DOI, which the arXiv id already covers
    #expect(paper.year == 2017)
    #expect(paper.abstract?.isEmpty == false)
    #expect(paper.landingURL?.absoluteString == "https://arxiv.org/abs/1706.03762")
    #expect(http.hosts == ["api.semanticscholar.org"])
}

@Test func papersTitleSearchRejectsADifferentPaper() async throws {
    // The service returns "Attention is all you need" whatever was asked.
    let http = standardHTTP()
    let paper = try await client(http).search(title: "Attention mechanisms in computer vision: a survey")
    // Crossref and arXiv, asked next, have nothing close either.
    #expect(paper == nil)
    #expect(http.hosts == ["api.semanticscholar.org", "api.crossref.org", "export.arxiv.org"])
}

@Test func papersTitleSearchFallsBackToCrossrefWhenRateLimited() async throws {
    let http = standardHTTP(semanticScholar: status(429, ["Retry-After": "2"]))
    let paper = try #require(try await client(http).search(title: "Deep Residual Learning for Image Recognition"))
    // Third result in the fixture: the first two are longer titles containing the same words.
    #expect(paper.doi == "10.1109/cvpr.2016.90")
    #expect(paper.title == "Deep Residual Learning for Image Recognition")
    #expect(paper.year == 2016)
    // Crossref had no abstract, so arXiv was asked for one (and had no such title here).
    #expect(http.hosts == ["api.semanticscholar.org", "api.crossref.org", "export.arxiv.org"])
    let crossref = try #require(http.requests[1].url)
    #expect(URLComponents(url: crossref, resolvingAgainstBaseURL: false)?.queryItems?
        .first { $0.name == "query.bibliographic" }?.value == "Deep Residual Learning for Image Recognition")
}

@Test func papersTitleSearchGetsTheAbstractFromArxiv() async throws {
    // Crossref knows the paper but, as usual, not its abstract.
    let crossrefOnly = #"{"status":"ok","message":{"items":[{"DOI":"10.5555/3295222.3295349","title":["Attention Is All You Need"],"author":[{"given":"Ashish","family":"Vaswani"}],"issued":{"date-parts":[[2017]]},"container-title":["NeurIPS"]}]}}"#
    let http = FakeHTTP { url in
        switch url.host {
        case "api.semanticscholar.org": return status(429)
        case "api.crossref.org": return ok(crossrefOnly)
        default: return ok(PapersFixtures.arxivAttention)
        }
    }
    let paper = try #require(try await client(http).search(title: "Attention is all you need"))
    #expect(paper.doi == "10.5555/3295222.3295349")   // identity from Crossref
    #expect(paper.venue == "NeurIPS")
    #expect(paper.abstract?.hasPrefix("The dominant sequence transduction models") == true)   // text from arXiv
    #expect(paper.arxivID == "1706.03762")
    #expect(paper.pdfURL?.absoluteString == "https://arxiv.org/pdf/1706.03762")
    let arxiv = try #require(http.requests.last?.url)
    #expect(URLComponents(url: arxiv, resolvingAgainstBaseURL: false)?.queryItems?
        .first { $0.name == "search_query" }?.value == "ti:\"attention is all you need\"")
}

@Test func papersTitleSearchFindsArxivOnlyPreprints() async throws {
    let http = FakeHTTP { url in
        switch url.host {
        case "api.semanticscholar.org": return status(429)
        case "api.crossref.org": return ok(#"{"status":"ok","message":{"items":[]}}"#)
        default: return ok(PapersFixtures.arxivAttention)
        }
    }
    let paper = try #require(try await client(http).search(title: "Attention Is All You Need"))
    #expect(paper.arxivID == "1706.03762")
    #expect(paper.authors.count == 8)
    // arXiv's search is fuzzy too: a different title is still refused.
    #expect(try await client(http).search(title: "Attention is not what you need at all") == nil)
}

@Test func papersTitleSearchThrowsOnlyWhenEveryServiceFails() async throws {
    await #expect(throws: PaperLookupError.http(status: 503)) {
        _ = try await client(FakeHTTP { _ in status(503) }).search(title: "Attention is all you need")
    }
    // One service answering "nothing" is an answer.
    let partly = FakeHTTP { url in url.host == "api.crossref.org" ? ok(#"{"status":"ok","message":{"items":[]}}"#) : status(503) }
    #expect(try await client(partly).search(title: "Attention is all you need") == nil)
}

@Test func papersTitleSearchTreats404AsNoMatch() async throws {
    let http = FakeHTTP { url in
        url.host == "api.semanticscholar.org" ? status(404) : ok(#"{"status":"ok","message":{"items":[]}}"#)
    }
    #expect(try await client(http).search(title: "A title nobody ever wrote down") == nil)
    #expect(try await client(http).search(title: "abc") == nil)   // too short to mean anything
}

@Test func papersErrorsAreSpecific() async {
    await #expect(throws: PaperLookupError.rateLimited(retryAfter: 7)) {
        _ = try await client(FakeHTTP { _ in status(429, ["Retry-After": "7"]) }).lookup(arxivID: "1706.03762")
    }
    await #expect(throws: PaperLookupError.http(status: 503)) {
        _ = try await client(FakeHTTP { _ in status(503) }).lookup(doi: "10.1038/nature14539")
    }
    await #expect(throws: PaperLookupError.malformedResponse) {
        _ = try await client(FakeHTTP { _ in ok("not json") }).lookup(doi: "10.1038/nature14539")
    }
}

@Test func papersTitleSimilarity() {
    #expect(PaperTitleSimilarity.score("Attention Is All You Need", "attention is all you need.") == 1)
    #expect(PaperTitleSimilarity.score("Über-résumé: naïve", "uber resume naive") == 1)
    #expect(PaperTitleSimilarity.score("Adam: A Method for Stochastic Optimization", "Adam: A Method for Stochastic Optimisation") > 0.9)
    // A reference that dropped the subtitle still matches.
    #expect(PaperTitleSimilarity.score("ImageNet large scale visual recognition challenge",
                                       "ImageNet Large Scale Visual Recognition Challenge: results and analysis")
        >= PaperTitleSimilarity.acceptThreshold)
    #expect(PaperTitleSimilarity.score("Deep Residual Learning for Image Recognition",
                                       "Deep Residual Learning for Image Recognition: A Survey") >= 0.86)
    #expect(PaperTitleSimilarity.score("Deep Residual Learning for Image Recognition",
                                       "Multiple butterflies recognition based on deep residual learning and image analyze") < 0.6)
    #expect(PaperTitleSimilarity.score("Deep learning", "Deep learning in neural networks: an overview") < 0.86)
    #expect(PaperTitleSimilarity.score("", "x") == 0)
}

/// Opt-in check against the real services: `COREADER_LIVE_PAPERS=1 swift test --filter livePaperLookups`
@Test(.enabled(if: ProcessInfo.processInfo.environment["COREADER_LIVE_PAPERS"] != nil))
func livePaperLookups() async throws {
    let live = PaperMetadataClient()
    let arxiv = try await live.resolve("https://arxiv.org/abs/1706.03762")
    #expect(arxiv.title == "Attention Is All You Need")
    let doi = try await live.resolve("10.1038/nature14539")
    #expect(doi.title == "Deep learning")
    let found = try await live.search(title: "Deep Residual Learning for Image Recognition")
    print("LIVE_SEARCH=\(found?.title ?? "nil") arxiv=\(found?.arxivID ?? "nil") doi=\(found?.doi ?? "nil") abstract=\(found?.abstract?.count ?? 0)")
    #expect(found != nil)
    #expect(try await live.search(title: "Zxqv blorptastic nonexistent paper title qwerty") == nil)
}

@Test func papersDownloadPDFWritesTheFile() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("coreader-pdf-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let http = standardHTTP()
    let meta = PaperMetadata(title: "Attention Is All You Need", arxivID: "1706.03762")
    let file = try await client(http).downloadPDF(meta, to: directory)
    #expect(file.lastPathComponent == "1706.03762.pdf")
    #expect(try Data(contentsOf: file).starts(with: Data("%PDF".utf8)))
    #expect(http.requests.first?.url?.absoluteString == "https://arxiv.org/pdf/1706.03762")

    // A paywall page is not saved as a PDF.
    let paywall = FakeHTTP { _ in ok("<html>Sign in</html>") }
    let paid = PaperMetadata(title: "Deep learning: a review!", pdfURL: URL(string: "http://www.nature.com/articles/nature14539.pdf"))
    await #expect(throws: PaperLookupError.notAPDF) { _ = try await client(paywall).downloadPDF(paid, to: directory) }
    await #expect(throws: PaperLookupError.noPDFAvailable) {
        _ = try await client(paywall).downloadPDF(PaperMetadata(title: "No link"), to: directory)
    }
    #expect(PaperMetadataClient.fileName(for: paid) == "deep-learning-a-review.pdf")
    #expect(PaperMetadataClient.fileName(for: PaperMetadata(title: "x", arxivID: "hep-th/9901001")) == "hep-th_9901001.pdf")
}

@Test func papersPacerSpacesRequestsToOneHost() async throws {
    let pacer = PaperRequestPacer(intervals: ["slow.example": 0.15])
    let started = Date()
    for _ in 0..<3 { try await pacer.wait(for: "slow.example") }
    let slow = Date().timeIntervalSince(started)
    #expect(slow >= 0.28)
    let free = Date()
    for _ in 0..<3 { try await pacer.wait(for: "other.example") }
    #expect(Date().timeIntervalSince(free) < 0.1)
}

@Test func papersMetadataRoundTripsThroughJSON() throws {
    let paper = PaperMetadata(title: "T", authors: ["A"], abstract: "x", year: 2020, venue: "V", doi: "10.1/x",
                              arxivID: "2001.00001", pdfURL: URL(string: "https://a/b.pdf"), landingURL: URL(string: "https://a/b"))
    #expect(try JSONDecoder().decode(PaperMetadata.self, from: JSONEncoder().encode(paper)) == paper)
}
