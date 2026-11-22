import Foundation

/// A web article after readability extraction, ready to be saved as one file.
public struct ArticleContent: Sendable, Equatable {
    public var title: String
    public var byline: String?
    public var siteName: String?
    public var sourceURL: URL
    public var publishedAt: Date?
    /// The article body as HTML, already reduced to the readable part.
    public var contentHTML: String
    public var excerpt: String?

    public init(
        title: String, byline: String? = nil, siteName: String? = nil, sourceURL: URL, publishedAt: Date? = nil,
        contentHTML: String, excerpt: String? = nil
    ) {
        self.title = title
        self.byline = byline
        self.siteName = siteName
        self.sourceURL = sourceURL
        self.publishedAt = publishedAt
        self.contentHTML = contentHTML
        self.excerpt = excerpt
    }
}

/// Turns an extracted article into the single HTML file the reader opens, and reads the
/// essentials back out of such a file.
public enum ArticlePackager {
    static let sourceMeta = "coreader:source-url"
    static let siteMeta = "coreader:site-name"
    static let publishedMeta = "coreader:published"

    /// A complete document that is valid both as HTML and as XML (the web reader loads
    /// it as XHTML). Scripts, event handlers, frames and forms are removed; links and
    /// images point at absolute URLs so they work from a file on disk.
    public static func html(for article: ArticleContent) -> String {
        let title = clean(article.title).isEmpty ? (article.sourceURL.host ?? "Article") : clean(article.title)
        let byline = article.byline.map(clean).flatMap { $0.isEmpty ? nil : $0 }
        let site = article.siteName.map(clean).flatMap { $0.isEmpty ? nil : $0 }
        let source = article.sourceURL.absoluteString
        let published = article.publishedAt.map { ISO8601DateFormatter().string(from: $0) }

        var head = """
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>\(text(title))</title>
        <meta name="generator" content="Coreader" />
        <meta name="\(sourceMeta)" content="\(attribute(source))" />
        <link rel="canonical" href="\(attribute(source))" />

        """
        if let byline { head += "<meta name=\"author\" content=\"\(attribute(byline))\" />\n" }
        if let site { head += "<meta name=\"\(siteMeta)\" content=\"\(attribute(site))\" />\n" }
        if let published { head += "<meta name=\"\(publishedMeta)\" content=\"\(published)\" />\n" }
        if let excerpt = article.excerpt.map(clean), !excerpt.isEmpty {
            head += "<meta name=\"description\" content=\"\(attribute(excerpt))\" />\n"
        }

        var details: [String] = []
        if let byline { details.append("<span class=\"coreader-byline\">\(text(byline))</span>") }
        if let site { details.append("<span class=\"coreader-site\">\(text(site))</span>") }
        if let date = article.publishedAt, let published {
            details.append("<time datetime=\"\(published)\">\(text(displayDate(date)))</time>")
        }
        var header = "<h1>\(text(title))</h1>\n"
        if !details.isEmpty { header += "<p class=\"coreader-meta\">\(details.joined(separator: " · "))</p>\n" }
        let host = article.sourceURL.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? source
        header += "<p class=\"coreader-source\"><a href=\"\(attribute(source))\">\(text(host))</a></p>"

        return """
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head>
        \(head)<style>
        body { max-width: 42em; margin: 0 auto; padding: 2em 1.2em; line-height: 1.6; font-family: Georgia, serif; }
        img, video, svg, figure { max-width: 100%; height: auto; }
        pre { overflow-x: auto; }
        .coreader-article-header { margin-bottom: 2em; }
        .coreader-meta, .coreader-source { font-size: 0.9em; opacity: 0.7; margin: 0.3em 0; }
        </style>
        </head>
        <body>
        <article>
        <header class="coreader-article-header">
        \(header)
        </header>
        <div class="coreader-article-body">
        \(sanitize(article.contentHTML, baseURL: article.sourceURL))
        </div>
        </article>
        </body>
        </html>

        """
    }

    /// Reads title, author and source back from a file written by `html(for:)`. Works on
    /// any HTML with the usual `<title>` and `<meta name="author">`; the source URL falls
    /// back to `<link rel="canonical">`.
    public static func metadata(fromHTML html: String) -> (title: String?, byline: String?, sourceURL: URL?) {
        // Everything of interest is in the head; do not scan a megabyte of body.
        let headEnd = html.range(of: "</head", options: .caseInsensitive)?.lowerBound ?? html.endIndex
        let characters = Array(html[..<headEnd])

        var title: String?, byline: String?, source: String?, canonical: String?
        var index = 0
        while index < characters.count {
            guard characters[index] == "<", let tag = parseTag(characters, at: index) else {
                index += 1
                continue
            }
            index = tag.end
            let attributes = Dictionary(tag.attributes.map { ($0.name.lowercased(), decodeEntities($0.value)) }, uniquingKeysWith: { first, _ in first })
            switch tag.name.lowercased() {
            case "title" where !tag.isEnd && title == nil:
                var end = index
                while end < characters.count, characters[end] != "<" { end += 1 }
                title = clean(decodeEntities(String(characters[index..<end])))
            case "meta":
                switch attributes["name"]?.lowercased() {
                case "author": byline = byline ?? attributes["content"]
                case sourceMeta: source = attributes["content"]
                default: break
                }
            case "link" where attributes["rel"]?.lowercased() == "canonical":
                canonical = attributes["href"]
            default: break
            }
        }
        func nonEmpty(_ value: String?) -> String? { value.map(clean).flatMap { $0.isEmpty ? nil : $0 } }
        return (nonEmpty(title), nonEmpty(byline), nonEmpty(source ?? canonical).flatMap(URL.init(string:)))
    }

    // MARK: Sanitising

    /// Elements removed together with everything inside them.
    private static let droppedWithContent: Set<String> = [
        "script", "style", "iframe", "form", "object", "applet", "template", "button", "select", "textarea",
        "noscript", "frameset", "noframes", "noembed", "head", "title", "dialog",
    ]
    /// Their content is raw text in HTML, so it is skipped to the end tag without parsing.
    private static let rawText: Set<String> = ["script", "style", "iframe", "textarea", "noscript", "noframes", "noembed", "title"]
    /// Removed, but their children stay.
    private static let unwrapped: Set<String> = ["html", "body", "frame"]
    /// Standalone elements that are removed.
    private static let droppedVoid: Set<String> = ["input", "link", "meta", "base", "embed", "param"]
    /// HTML elements that never have an end tag; XML needs them self-closed.
    private static let void: Set<String> = [
        "area", "br", "col", "hr", "img", "source", "track", "wbr", "input", "link", "meta", "base", "embed", "param",
    ]
    private static let impliedEnd: Set<String> = ["p", "li", "dt", "dd", "tr", "td", "th", "option"]
    private static let urlAttributes: Set<String> = ["href", "src", "poster", "cite", "xlink:href", "data-src"]
    private static let droppedAttributes: Set<String> = ["srcdoc", "formaction", "ping", "action", "integrity", "nonce"]

    /// Body HTML made safe and well-formed: no active content, absolute URLs, every tag
    /// closed and every entity in a shape an XML parser accepts. This is a tokenizer, not
    /// a browser: it repairs unclosed and stray tags but does not reorder misnested ones.
    static func sanitize(_ html: String, baseURL: URL) -> String {
        let characters = Array(html)
        var out = ""
        var index = 0
        // Name and nesting depth of the element currently being dropped.
        var dropping: (name: String, depth: Int)?
        // Elements currently open, as written, so every one gets its end tag.
        var open: [String] = []

        while index < characters.count {
            guard characters[index] == "<" else {
                var end = index
                while end < characters.count, characters[end] != "<" { end += 1 }
                if dropping == nil { out += text(decodeEntities(String(characters[index..<end]))) }
                index = end
                continue
            }
            // Comments, doctype, processing instructions and CDATA markers carry nothing to read.
            if starts(characters, index, "<!--") {
                index = find(characters, "-->", from: index + 4).map { $0 + 3 } ?? characters.count
                continue
            }
            if index + 1 < characters.count, characters[index + 1] == "!" || characters[index + 1] == "?" {
                index = find(characters, ">", from: index + 1).map { $0 + 1 } ?? characters.count
                continue
            }
            guard let tag = parseTag(characters, at: index) else {
                // A lone "<" in text, as in "a < b".
                if dropping == nil { out += "&lt;" }
                index += 1
                continue
            }
            index = tag.end
            let name = tag.name.lowercased()

            if let current = dropping {
                if name == current.name {
                    let depth = current.depth + (tag.isEnd ? -1 : (tag.selfClosing ? 0 : 1))
                    dropping = depth <= 0 ? nil : (current.name, depth)
                }
                continue
            }
            if droppedWithContent.contains(name) {
                guard !tag.isEnd, !tag.selfClosing else { continue }
                if rawText.contains(name) {
                    // "</script" may be followed by anything up to ">".
                    if let close = find(characters, "</" + name, from: index, caseInsensitive: true) {
                        index = find(characters, ">", from: close).map { $0 + 1 } ?? characters.count
                    } else {
                        index = characters.count
                    }
                } else {
                    dropping = (name, 1)
                }
                continue
            }
            if unwrapped.contains(name) || droppedVoid.contains(name) { continue }

            if tag.isEnd {
                // Close whatever was left open inside it; an end tag with no start is dropped.
                guard !void.contains(name), let match = open.lastIndex(where: { $0.lowercased() == name }) else { continue }
                for element in open[match...].reversed() { out += "</\(element)>" }
                open.removeSubrange(match...)
                continue
            }
            let isEmpty = void.contains(name) || tag.selfClosing
            if !isEmpty {
                // HTML lets these end silently when a sibling starts; XML does not.
                if impliedEnd.contains(name), let top = open.last, top.lowercased() == name {
                    out += "</\(top)>"
                    open.removeLast()
                }
                open.append(tag.name)
            }
            out += "<\(tag.name)"
            var seen = Set<String>()
            for raw in tag.attributes {
                let key = raw.name.lowercased()
                // XML rejects a repeated attribute and names that are not names.
                guard isXMLName(raw.name), seen.insert(key).inserted else { continue }
                if key.hasPrefix("on") || droppedAttributes.contains(key) { continue }
                var value = decodeEntities(raw.value)
                if urlAttributes.contains(key) {
                    guard let resolved = resolve(value, base: baseURL) else { continue }
                    value = resolved
                } else if key == "srcset" || key == "imagesrcset" {
                    value = resolveSrcset(value, base: baseURL)
                } else if key == "style" {
                    let lower = value.lowercased()
                    if lower.contains("javascript:") || lower.contains("expression(") || lower.contains("@import") || lower.contains("behavior:") {
                        continue
                    }
                }
                out += " \(raw.name)=\"\(attribute(value))\""
            }
            out += isEmpty ? " />" : ">"
        }
        for element in open.reversed() { out += "</\(element)>" }
        return out
    }

    struct Tag {
        var name: String
        var isEnd: Bool
        var selfClosing: Bool
        var attributes: [(name: String, value: String)]
        /// Index just past the closing ">".
        var end: Int
    }

    /// Parses the tag starting at `start` ("<"). Nil when what follows is not a tag.
    static func parseTag(_ c: [Character], at start: Int) -> Tag? {
        var i = start + 1
        var isEnd = false
        if i < c.count, c[i] == "/" { isEnd = true; i += 1 }
        guard i < c.count, c[i].isLetter, c[i].isASCII else { return nil }
        var name = ""
        while i < c.count, !c[i].isWhitespace, c[i] != ">", c[i] != "/" { name.append(c[i]); i += 1 }
        guard isXMLName(name) else { return nil }

        var attributes: [(name: String, value: String)] = []
        var selfClosing = false
        while true {
            while i < c.count, c[i].isWhitespace { i += 1 }
            guard i < c.count else { return nil }   // ran out before ">": not a tag after all
            if c[i] == ">" { i += 1; break }
            if c[i] == "/" {
                selfClosing = i + 1 < c.count && c[i + 1] == ">"
                i += 1
                continue
            }
            var key = ""
            while i < c.count, !c[i].isWhitespace, c[i] != "=", c[i] != ">", c[i] != "/" { key.append(c[i]); i += 1 }
            while i < c.count, c[i].isWhitespace { i += 1 }
            var value = ""
            if i < c.count, c[i] == "=" {
                i += 1
                while i < c.count, c[i].isWhitespace { i += 1 }
                if i < c.count, c[i] == "\"" || c[i] == "'" {
                    let quote = c[i]
                    i += 1
                    while i < c.count, c[i] != quote { value.append(c[i]); i += 1 }
                    guard i < c.count else { return nil }
                    i += 1
                } else {
                    while i < c.count, !c[i].isWhitespace, c[i] != ">" { value.append(c[i]); i += 1 }
                }
            } else {
                // HTML boolean attribute ("controls"); XML wants a value.
                value = key
            }
            if !key.isEmpty { attributes.append((key, value)) }
        }
        return Tag(name: name, isEnd: isEnd, selfClosing: selfClosing, attributes: attributes, end: i)
    }

    private static func isXMLName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, first.isASCII, first.properties.isAlphabetic || first == "_" else { return false }
        return name.unicodeScalars.allSatisfy { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0) || "-_.:".unicodeScalars.contains($0)) }
    }

    // MARK: URLs

    /// Absolute form of a link or image address. Nil for addresses that run code.
    static func resolve(_ value: String, base: URL) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Browsers ignore whitespace and control characters inside the scheme.
        let scheme = trimmed.unicodeScalars.filter { $0.value > 0x20 }.prefix(16).map { String($0).lowercased() }.joined()
        if scheme.hasPrefix("javascript:") || scheme.hasPrefix("vbscript:") || scheme.hasPrefix("data:text/html") { return nil }
        if trimmed.isEmpty || trimmed.hasPrefix("#") || scheme.hasPrefix("data:") { return trimmed }
        return URL(string: trimmed, relativeTo: base)?.absoluteString ?? trimmed
    }

    /// "a.jpg 1x, b.jpg 2x" with each address made absolute.
    static func resolveSrcset(_ value: String, base: URL) -> String {
        // Commas also appear inside data: URLs; those sets are left as they are.
        guard !value.lowercased().contains("data:") else { return value }
        return value.split(separator: ",").map { candidate -> String in
            let parts = candidate.split(whereSeparator: \.isWhitespace)
            guard let url = parts.first, let resolved = resolve(String(url), base: base) else { return "" }
            return ([resolved] + parts.dropFirst().map(String.init)).joined(separator: " ")
        }
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    // MARK: Text and entities

    private static func clean(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    /// Escapes for element content. Characters XML forbids outright are removed.
    static func text(_ value: String) -> String {
        var out = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case _ where scalar.value < 0x20 && scalar != "\n" && scalar != "\t" && scalar != "\r": continue
            case _ where scalar.value == 0xFFFE || scalar.value == 0xFFFF: continue
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    static func attribute(_ value: String) -> String {
        text(value).replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// XML knows five named entities; HTML has hundreds. Everything is decoded to the
    /// character itself and escaped again on the way out, so `&nbsp;` cannot break the
    /// XML parser. An unknown name stays as literal text.
    static func decodeEntities(_ value: String) -> String {
        guard value.contains("&") else { return value }
        var out = ""
        var rest = Substring(value)
        while let ampersand = rest.firstIndex(of: "&") {
            out += rest[..<ampersand]
            let after = rest[rest.index(after: ampersand)...]
            if let semicolon = after.prefix(12).firstIndex(of: ";") {
                let name = String(after[..<semicolon])
                if let decoded = decodeEntity(name) {
                    out += decoded
                    rest = after[after.index(after: semicolon)...]
                    continue
                }
            }
            out += "&"
            rest = after
        }
        out += rest
        return out
    }

    private static func decodeEntity(_ name: String) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let code = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
            return code.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return namedEntities[name]
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{A0}",
        "mdash": "—", "ndash": "–", "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "sbquo": "‚", "bdquo": "„", "laquo": "«", "raquo": "»", "lsaquo": "‹", "rsaquo": "›",
        "copy": "©", "reg": "®", "trade": "™", "middot": "·", "bull": "•", "deg": "°", "plusmn": "±",
        "times": "×", "divide": "÷", "minus": "−", "frac12": "½", "frac14": "¼", "frac34": "¾",
        "euro": "€", "pound": "£", "yen": "¥", "cent": "¢", "sect": "§", "para": "¶", "dagger": "†", "Dagger": "‡",
        "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "harr": "↔", "rArr": "⇒", "lArr": "⇐",
        "prime": "′", "Prime": "″", "le": "≤", "ge": "≥", "ne": "≠", "asymp": "≈", "infin": "∞", "micro": "µ",
        "thinsp": "\u{2009}", "ensp": "\u{2002}", "emsp": "\u{2003}", "zwnj": "\u{200C}", "zwj": "\u{200D}", "shy": "\u{AD}",
        "agrave": "à", "aacute": "á", "acirc": "â", "atilde": "ã", "auml": "ä", "aring": "å", "aelig": "æ", "ccedil": "ç",
        "egrave": "è", "eacute": "é", "ecirc": "ê", "euml": "ë", "igrave": "ì", "iacute": "í", "icirc": "î", "iuml": "ï",
        "ntilde": "ñ", "ograve": "ò", "oacute": "ó", "ocirc": "ô", "otilde": "õ", "ouml": "ö", "oslash": "ø",
        "ugrave": "ù", "uacute": "ú", "ucirc": "û", "uuml": "ü", "yacute": "ý", "szlig": "ß",
        "Agrave": "À", "Aacute": "Á", "Acirc": "Â", "Auml": "Ä", "Aring": "Å", "AElig": "Æ", "Ccedil": "Ç",
        "Egrave": "È", "Eacute": "É", "Ecirc": "Ê", "Iacute": "Í", "Ntilde": "Ñ", "Oacute": "Ó", "Ouml": "Ö",
        "Oslash": "Ø", "Uacute": "Ú", "Uuml": "Ü",
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε", "theta": "θ", "lambda": "λ", "mu": "μ",
        "pi": "π", "sigma": "σ", "tau": "τ", "phi": "φ", "omega": "ω", "Delta": "Δ", "Sigma": "Σ", "Omega": "Ω",
    ]

    // MARK: Scanning helpers

    private static func starts(_ c: [Character], _ index: Int, _ prefix: String) -> Bool {
        let wanted = Array(prefix)
        guard index + wanted.count <= c.count else { return false }
        for offset in wanted.indices where c[index + offset] != wanted[offset] { return false }
        return true
    }

    private static func find(_ c: [Character], _ needle: String, from start: Int, caseInsensitive: Bool = false) -> Int? {
        let wanted = Array(caseInsensitive ? needle.lowercased() : needle)
        guard !wanted.isEmpty, start <= c.count - wanted.count else { return nil }
        var index = start
        while index <= c.count - wanted.count {
            var matched = true
            for offset in wanted.indices {
                let character = c[index + offset]
                if caseInsensitive ? String(character).lowercased() != String(wanted[offset]) : character != wanted[offset] {
                    matched = false
                    break
                }
            }
            if matched { return index }
            index += 1
        }
        return nil
    }
}
