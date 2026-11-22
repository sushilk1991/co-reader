import CoreaderKit
import WebKit

/// Loads a web page in an unseen web view and pulls out the readable article.
@MainActor
final class ArticleFetcher: NSObject, WKNavigationDelegate {
    enum Failure: LocalizedError {
        case loadFailed(String), nothingReadable
        var errorDescription: String? {
            switch self {
            case .loadFailed(let reason): "The page did not load (\(reason))."
            case .nothingReadable: "No readable article was found on that page."
            }
        }
    }

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Error>?

    func fetch(_ url: URL) async throws -> ArticleContent {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1100, height: 1400), configuration: config)
        webView.navigationDelegate = self
        self.webView = webView
        defer { self.webView = nil }

        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            continuation = c
            webView.load(URLRequest(url: url, timeoutInterval: 30))
        }
        // Give client-rendered pages a moment to fill in.
        try? await Task.sleep(for: .milliseconds(900))

        let result = try await webView.evaluateJavaScript(Self.extractor)
        guard let dict = result as? [String: Any], let html = dict["html"] as? String,
              (dict["length"] as? Int ?? 0) > 400 else { throw Failure.nothingReadable }
        func s(_ k: String) -> String? { (dict[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let date = s("published").flatMap { ISO8601DateFormatter().date(from: $0) }
        return ArticleContent(title: s("title") ?? url.host ?? "Article", byline: s("byline"), siteName: s("site"),
                              sourceURL: webView.url ?? url, publishedAt: date, contentHTML: html, excerpt: s("excerpt"))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: Failure.loadFailed(error.localizedDescription))
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: Failure.loadFailed(error.localizedDescription))
        continuation = nil
    }

    /// A compact readability pass: pick the element holding the most paragraph text,
    /// then drop navigation, ads and scripts from a copy of it.
    private static let extractor = """
    (() => {
      const meta = (...names) => { for (const n of names) { const el = document.querySelector(`meta[property="${n}"], meta[name="${n}"]`); if (el?.content) return el.content.trim() } return '' }
      const candidates = [...document.querySelectorAll('article, main, [role="main"], .post, .entry-content, .article-body, .post-content, #content, section, div')]
      let best = document.body, bestScore = 0
      for (const el of candidates) {
        const ps = el.querySelectorAll(':scope > p, :scope > div > p, :scope > section > p, :scope > * > * > p')
        let score = 0
        for (const p of ps) { const n = p.textContent.trim().length; if (n > 60) score += n }
        if (el.matches('article, main, [role="main"]')) score *= 1.35
        const linkLen = [...el.querySelectorAll('a')].reduce((n, a) => n + a.textContent.length, 0)
        const total = el.textContent.length || 1
        score *= 1 - Math.min(0.9, linkLen / total)
        if (score > bestScore) { best = el; bestScore = score }
      }
      const copy = best.cloneNode(true)
      copy.querySelectorAll('script, style, noscript, iframe, form, nav, aside, footer, header, button, input, svg, dialog, [aria-hidden="true"], [role="navigation"], [role="complementary"], .share, .social, .newsletter, .related, .comments, .ad, .ads, .advert, .promo, .sidebar').forEach(e => e.remove())
      copy.querySelectorAll('*').forEach(e => {
        for (const a of [...e.attributes]) {
          const n = a.name
          if (n.startsWith('on') || n === 'style' || n === 'class' || n === 'id' || n.startsWith('data-')) {
            if (n === 'data-src' && e.tagName === 'IMG' && !e.getAttribute('src')) e.setAttribute('src', a.value)
            e.removeAttribute(n)
          }
        }
        if (e.tagName === 'IMG') { const s = e.currentSrc || e.src; if (s) e.setAttribute('src', new URL(s, location.href).href); e.removeAttribute('srcset'); e.removeAttribute('sizes'); e.removeAttribute('loading') }
        if (e.tagName === 'A' && e.getAttribute('href')) e.setAttribute('href', new URL(e.getAttribute('href'), location.href).href)
      })
      const h1 = document.querySelector('article h1, main h1, h1')
      const title = meta('og:title', 'twitter:title') || h1?.textContent.trim() || document.title
      copy.querySelectorAll('h1').forEach(e => { if (e.textContent.trim() === title.trim()) e.remove() })
      return {
        html: copy.innerHTML, length: copy.textContent.trim().length, title,
        byline: meta('author', 'article:author', 'parsely-author') || document.querySelector('[rel="author"], .author, .byline')?.textContent.trim().replace(/^by\\s+/i, '') || '',
        site: meta('og:site_name') || location.hostname.replace(/^www\\./, ''),
        excerpt: meta('og:description', 'description'),
        published: meta('article:published_time', 'date', 'parsely-pub-date'),
      }
    })()
    """
}
