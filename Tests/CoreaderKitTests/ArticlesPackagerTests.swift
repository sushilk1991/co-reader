import Foundation
import Testing
@testable import CoreaderKit

private let source = URL(string: "https://www.example.com/blog/2026/great-post?ref=home")!

private func article(_ body: String, title: String = "A Great Post", byline: String? = "Ada Lovelace") -> ArticleContent {
    ArticleContent(
        title: title, byline: byline, siteName: "Example Blog", sourceURL: source,
        publishedAt: Date(timeIntervalSince1970: 1_773_230_400),   // 2026-03-11T12:00:00Z
        contentHTML: body, excerpt: "What the post is about."
    )
}

private func sanitize(_ html: String) -> String {
    ArticlePackager.sanitize(html, baseURL: source)
}

/// The packaged file must load as XML, since the web reader opens it as XHTML.
private func isWellFormedXML(_ document: String) -> Bool {
    let parser = XMLParser(data: Data(document.utf8))
    return parser.parse()
}

@Test func articlePackagesACompleteDocument() {
    let html = ArticlePackager.html(for: article("<p>Hello <em>world</em>.</p>"))
    #expect(html.hasPrefix("<!DOCTYPE html>\n<html xmlns=\"http://www.w3.org/1999/xhtml\">"))
    #expect(html.contains("<title>A Great Post</title>"))
    #expect(html.contains("<meta name=\"author\" content=\"Ada Lovelace\" />"))
    #expect(html.contains("<meta name=\"coreader:source-url\" content=\"https://www.example.com/blog/2026/great-post?ref=home\" />"))
    #expect(html.contains("<meta name=\"coreader:site-name\" content=\"Example Blog\" />"))
    #expect(html.contains("<meta name=\"coreader:published\" content=\"2026-03-11T12:00:00Z\" />"))
    #expect(html.contains("<meta name=\"description\" content=\"What the post is about.\" />"))
    #expect(html.contains("<h1>A Great Post</h1>"))
    #expect(html.contains("<span class=\"coreader-byline\">Ada Lovelace</span>"))
    #expect(html.contains("<time datetime=\"2026-03-11T12:00:00Z\">11 March 2026</time>"))
    #expect(html.contains("<a href=\"https://www.example.com/blog/2026/great-post?ref=home\">example.com</a>"))
    #expect(html.contains("<p>Hello <em>world</em>.</p>"))
    #expect(isWellFormedXML(html))
}

@Test func articleMetadataRoundTrips() {
    let tricky = article("<p>x</p>", title: "Q&A: “Fish” <and> Chips", byline: "O'Brien & Sons")
    let html = ArticlePackager.html(for: tricky)
    #expect(isWellFormedXML(html))
    let meta = ArticlePackager.metadata(fromHTML: html)
    #expect(meta.title == "Q&A: “Fish” <and> Chips")
    #expect(meta.byline == "O'Brien & Sons")
    #expect(meta.sourceURL == source)

    // Optional pieces left out.
    let bare = ArticleContent(title: "  ", sourceURL: source, contentHTML: "<p>x</p>")
    let bareHTML = ArticlePackager.html(for: bare)
    #expect(isWellFormedXML(bareHTML))
    #expect(!bareHTML.contains("name=\"author\""))
    #expect(!bareHTML.contains("class=\"coreader-meta\""))
    let bareMeta = ArticlePackager.metadata(fromHTML: bareHTML)
    #expect(bareMeta.title == "www.example.com")   // falls back to the host
    #expect(bareMeta.byline == nil)
    #expect(bareMeta.sourceURL == source)
}

@Test func articleMetadataReadsOrdinaryHTMLToo() {
    let page = """
    <html><head><TITLE>Plain &amp; Simple</TITLE>
    <meta content='Grace Hopper' name='author'>
    <link rel="canonical" href="https://example.org/plain">
    </head><body><title>not this</title><meta name="author" content="nor this"></body></html>
    """
    let meta = ArticlePackager.metadata(fromHTML: page)
    #expect(meta.title == "Plain & Simple")
    #expect(meta.byline == "Grace Hopper")
    #expect(meta.sourceURL?.absoluteString == "https://example.org/plain")
    let nothing = ArticlePackager.metadata(fromHTML: "just text")
    #expect(nothing.title == nil && nothing.byline == nil && nothing.sourceURL == nil)
}

@Test func articleStripsActiveContent() {
    let dirty = """
    <p onclick="steal()" ONMOUSEOVER='x()' class="lead">Text</p>
    <script type="text/javascript">if (a < b && c > d) { document.write("</p>"); }</script>
    <SCRIPT>alert(1)</SCRIPT >
    <style>p { color: red }</style>
    <iframe src="https://ads.example/frame"><p>fallback</p></iframe>
    <form action="/subscribe"><p>Subscribe</p><input type="email"><button>Go</button></form>
    <object data="movie.swf"><param name="x" value="y"><embed src="movie.swf"></object>
    <noscript><img src="tracker.gif"></noscript>
    <a href="javascript:alert(1)">bad</a> <a href=" JaVa\tScript:alert(1)">worse</a>
    <a href="data:text/html,<script>alert(1)</script>">data</a>
    <img src="pic.jpg" onerror="alert(1)" srcdoc="x">
    <div style="background:url(javascript:alert(1))">styled</div>
    <!-- a comment with <script> inside -->
    <p>After</p>
    """
    let clean = sanitize(dirty)
    for forbidden in ["script", "alert", "steal", "onclick", "onmouseover", "onerror", "iframe", "ads.example", "<form",
                      "Subscribe", "<input", "<button", "<object", "<embed", "movie.swf", "tracker.gif", "javascript",
                      "srcdoc", "<style", "color: red", "comment", "fallback", "style="] {
        #expect(!clean.lowercased().contains(forbidden.lowercased()), "still contains \(forbidden)")
    }
    #expect(clean.contains("<p class=\"lead\">Text</p>"))
    #expect(clean.contains("<a>bad</a>"))
    #expect(clean.contains("<a>worse</a>"))
    #expect(clean.contains("<img src=\"https://www.example.com/blog/2026/pic.jpg\" />"))
    #expect(clean.contains("<div>styled</div>"))
    #expect(clean.contains("<p>After</p>"))
    #expect(isWellFormedXML("<root>\(clean)</root>"))
}

@Test func articleResolvesRelativeURLs() {
    let body = """
    <img src="images/a.png" alt="A"><img src="/abs/b.png"><img src="//cdn.example.net/c.png">
    <img src="https://other.example/d.png"><img src="data:image/png;base64,AAAA">
    <a href="../older">older</a> <a href="#section-2">jump</a> <a href="mailto:a@b.c">mail</a> <a href="?page=2">next</a>
    <img srcset="small.jpg 480w, /large.jpg 2x" src="small.jpg">
    <video poster="poster.jpg" controls><source src="clip.mp4" type="video/mp4"></video>
    <blockquote cite="/quoted">q</blockquote>
    """
    let clean = sanitize(body)
    #expect(clean.contains("src=\"https://www.example.com/blog/2026/images/a.png\""))
    #expect(clean.contains("src=\"https://www.example.com/abs/b.png\""))
    #expect(clean.contains("src=\"https://cdn.example.net/c.png\""))
    #expect(clean.contains("src=\"https://other.example/d.png\""))
    #expect(clean.contains("src=\"data:image/png;base64,AAAA\""))
    #expect(clean.contains("href=\"https://www.example.com/blog/older\""))
    #expect(clean.contains("href=\"#section-2\""))
    #expect(clean.contains("href=\"mailto:a@b.c\""))
    #expect(clean.contains("href=\"https://www.example.com/blog/2026/great-post?page=2\""))
    #expect(clean.contains("srcset=\"https://www.example.com/blog/2026/small.jpg 480w, https://www.example.com/large.jpg 2x\""))
    #expect(clean.contains("poster=\"https://www.example.com/blog/2026/poster.jpg\""))
    #expect(clean.contains("<video poster=\"https://www.example.com/blog/2026/poster.jpg\" controls=\"controls\">"))
    #expect(clean.contains("<source src=\"https://www.example.com/blog/2026/clip.mp4\" type=\"video/mp4\" />"))
    #expect(clean.contains("cite=\"https://www.example.com/quoted\""))
    #expect(isWellFormedXML("<root>\(clean)</root>"))
}

@Test func articleOutputIsXMLSafe() {
    let body = """
    <p>Caf&eacute;&nbsp;&mdash; 5 &lt; 6 &amp; 7 > 3, AT&T, a < b, &unknown; &#8217;s &#x1F600;</p>
    <br><hr><img src=x.png alt=unquoted width=10>
    <input type=checkbox checked>
    <p title="say &quot;hi&quot; <now>" data-x='single "double"' class=a class=b 1bad="x">attr</p>
    <ul><li>one<li>two</ul>
    <p>unclosed <b>bold <i>both</p>
    </div><span>stray end before</span>
    <svg viewBox="0 0 10 10"><path d="M0 0L10 10"/><circle cx="5" cy="5" r="2" /></svg>
    <td>cell\u{0B}with\u{01}controls</td>
    <p>tail
    """
    let clean = sanitize(body)
    #expect(clean.contains("Café\u{A0}— 5 &lt; 6 &amp; 7 &gt; 3, AT&amp;T, a &lt; b, &amp;unknown; ’s 😀"))
    #expect(clean.contains("<br /><hr /><img src=\"https://www.example.com/blog/2026/x.png\" alt=\"unquoted\" width=\"10\" />"))
    #expect(clean.contains("<p title=\"say &quot;hi&quot; &lt;now&gt;\" data-x=\"single &quot;double&quot;\" class=\"a\">attr</p>"))
    #expect(clean.contains("<ul><li>one</li><li>two</li></ul>"))
    #expect(clean.contains("<p>unclosed <b>bold <i>both</i></b></p>"))
    #expect(clean.contains("<span>stray end before</span>"))
    #expect(clean.contains("<svg viewBox=\"0 0 10 10\"><path d=\"M0 0L10 10\" /><circle cx=\"5\" cy=\"5\" r=\"2\" /></svg>"))
    #expect(clean.contains("cellwithcontrols"))
    #expect(clean.hasSuffix("</p>"))
    #expect(isWellFormedXML("<root>\(clean)</root>"))

    #expect(isWellFormedXML(ArticlePackager.html(for: article(body))))
    #expect(isWellFormedXML(ArticlePackager.html(for: article("<p>broken <a href=\"x"))))
    #expect(isWellFormedXML(ArticlePackager.html(for: article(""))))
}

@Test func articleKeepsOrdinaryMarkupUntouched() {
    let body = "<h2 id=\"intro\">Intro</h2><p>Some <a href=\"https://example.org/x?a=1&amp;b=2\">link</a> and <code>code</code>.</p>"
        + "<figure><img src=\"https://example.org/i.png\" alt=\"An image\" /><figcaption>Caption</figcaption></figure>"
        + "<pre><code>let x = 1\n  indented</code></pre><table><tr><td>1</td></tr></table>"
    #expect(sanitize(body) == body)
}

@Test func articleEntityDecoding() {
    #expect(ArticlePackager.decodeEntities("a &amp; b &lt;c&gt; &quot;d&quot; &#39;e&#x27; &nbsp;") == "a & b <c> \"d\" 'e' \u{A0}")
    #expect(ArticlePackager.decodeEntities("R&D &; &#; &#xZZ; &toolongtobeanentityname; 100%") == "R&D &; &#; &#xZZ; &toolongtobeanentityname; 100%")
    #expect(ArticlePackager.resolve("  /a b  ", base: source) == "https://www.example.com/a%20b")
    #expect(ArticlePackager.resolve("vbscript:x", base: source) == nil)
}
