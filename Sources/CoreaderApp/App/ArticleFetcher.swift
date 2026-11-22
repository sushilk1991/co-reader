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
            // Some pages never report that they finished; whatever has loaded by then is used.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(35))
                self?.resume(nil)
            }
        }
        // Give client-rendered pages a moment to fill in.
        try? await Task.sleep(for: .milliseconds(900))

        let result = try await webView.evaluateJavaScript(Self.extractor)
        guard let dict = result as? [String: Any], let html = dict["html"] as? String,
              (dict["length"] as? Int ?? 0) > 400 else { throw Failure.nothingReadable }
        func s(_ k: String) -> String? { (dict[k] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        let date = s("published").flatMap { ISO8601DateFormatter().date(from: $0) }
        let host = (webView.url ?? url).host?.replacingOccurrences(of: "www.", with: "")
        // A site name that only repeats the address adds nothing next to the source link.
        let site = s("site").flatMap { $0 == host ? nil : $0 }
        return ArticleContent(title: s("title") ?? url.host ?? "Article", byline: s("byline"), siteName: site,
                              sourceURL: webView.url ?? url, publishedAt: date, contentHTML: html, excerpt: s("excerpt"))
    }

    /// Ends the wait exactly once, whichever of load, failure, crash or deadline comes first.
    private func resume(_ failure: Failure?) {
        guard let continuation else { return }
        self.continuation = nil
        if let failure { continuation.resume(throwing: failure) } else { continuation.resume() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { resume(nil) }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resume(.loadFailed(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resume(.loadFailed(error.localizedDescription))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        resume(.loadFailed("the page stopped responding"))
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
      // Old pages lay text out with tables and <font>; keep the words, drop the scaffolding.
      // A table stays only when it looks like data: several rows of several short cells.
      for (const table of [...copy.querySelectorAll('table')].reverse()) {
        const rows = [...table.querySelectorAll('tr')]
        const cells = [...table.querySelectorAll('td, th')]
        const isData = rows.length >= 2 && cells.length >= rows.length * 2 && cells.every(c => c.textContent.trim().length < 200)
        if (isData) continue
        const div = document.createElement('div')
        for (const cell of cells.length ? cells : [table]) { const part = document.createElement('div'); part.append(...cell.childNodes); div.append(part) }
        table.replaceWith(div)
      }
      copy.querySelectorAll('font, center, span').forEach(e => e.replaceWith(...e.childNodes))
      copy.querySelectorAll('img').forEach(e => {
        const w = parseInt(e.getAttribute('width') || '0'), h = parseInt(e.getAttribute('height') || '0')
        if ((w && w < 24) || (h && h < 24) || /spacer|trans_?1x1|pixel/i.test(e.getAttribute('src') || '')) e.remove()
      })
      copy.querySelectorAll('div, p').forEach(e => { if (!e.textContent.trim() && !e.querySelector('img, picture, video')) e.remove() })
      const h1 = document.querySelector('article h1, main h1, h1')
      const title = meta('og:title', 'twitter:title') || h1?.textContent.trim() || document.title
      copy.querySelectorAll('h1').forEach(e => { if (e.textContent.trim() === title.trim()) e.remove() })
      let html = copy.innerHTML
      // Pages that separate paragraphs with double line breaks get real paragraphs.
      if (copy.querySelectorAll('p').length < 3) html = '<p>' + html.replace(/(<br\\s*\\/?>\\s*){2,}/gi, '</p><p>') + '</p>'
      return {
        html, length: copy.textContent.trim().length, title,
        byline: meta('author', 'article:author', 'parsely-author') || document.querySelector('[rel="author"], .author, .byline')?.textContent.trim().replace(/^by\\s+/i, '') || '',
        site: meta('og:site_name') || location.hostname.replace(/^www\\./, ''),
        excerpt: meta('og:description', 'description'),
        published: meta('article:published_time', 'date', 'parsely-pub-date'),
      }
    })()
    """
}
