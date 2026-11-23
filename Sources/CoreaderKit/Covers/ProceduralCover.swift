import Foundation

/// A cover drawn in code, shown the moment a book without one is imported and replaced
/// if an AI cover arrives. Same palettes and motif families as `CoverPromptBuilder`, so
/// the two kinds sit together on a shelf.
public enum ProceduralCover {
    /// A self-contained SVG document. Deterministic for a given brief and size.
    public static func svg(for brief: CoverBrief, width: Int = 800, height: Int = 1200) -> String {
        let w = Double(max(width, 60))
        let h = Double(max(height, 90))
        let palette = CoverPalette.palette(for: brief)
        let motif = CoverMotif.motif(for: brief)
        var rng = SplitMix64(seed: brief.seed)

        let margin = (w * 0.09).rounded()
        let title = layoutTitle(brief.displayTitle, width: w - margin * 2, coverWidth: w)
        let titleTop = margin * 1.05
        let titleBottom = titleTop + Double(title.lines.count) * title.lineHeight

        let authorSize = (w * 0.03).rounded()
        let authorBaseline = h - margin
        let author = brief.authorLine.map { fit($0.uppercased(), size: authorSize, tracking: 0.16, width: w - margin * 2) }

        // The artwork gets everything between the title and the author line.
        let artTop = titleBottom + margin * 0.55
        let artBottom = author == nil ? h - margin : authorBaseline - authorSize * 2.6
        let art = Rect(x: 0, y: artTop, w: w, h: max(artBottom - artTop, h * 0.2))

        var out = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(n(w)) \(n(h))" width="\(n(w))" height="\(n(h))" \
        role="img" aria-label="\(escape(brief.displayTitle))">
        <defs>
        <clipPath id="art"><rect x="0" y="\(n(art.y))" width="\(n(w))" height="\(n(art.h))"/></clipPath>
        <filter id="grain" x="0" y="0" width="100%" height="100%">
        <feTurbulence type="fractalNoise" baseFrequency="0.85" numOctaves="2" seed="\(brief.seed % 997)"/>
        <feColorMatrix type="matrix" values="0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0.55 0 0 0 -0.2"/>
        </filter>
        </defs>
        <rect width="\(n(w))" height="\(n(h))" fill="\(palette.ground)"/>
        <g clip-path="url(#art)" fill="none" stroke="\(palette.primary)" stroke-linecap="round">

        """
        out += draw(motif, in: art, margin: margin, palette: palette, rng: &rng)
        out += "</g>\n"

        let fonts = "'Iowan Old Style', 'Palatino Linotype', Palatino, 'Hoefler Text', Georgia, 'Times New Roman', serif"
        // One <text> per line with an absolute position: some renderers (AppKit's among
        // them) ignore `dy` on <tspan> and would set every line on top of the first.
        for (index, line) in title.lines.enumerated() {
            let y = titleTop + title.size * 0.82 + Double(index) * title.lineHeight
            out += "<text x=\"\(n(margin))\" y=\"\(n(y))\" font-family=\"\(fonts)\" "
                + "font-size=\"\(n(title.size))\" letter-spacing=\"\(n(-title.size * 0.012))\" fill=\"\(palette.primary)\">\(escape(line))</text>\n"
        }

        if let author {
            out += "<text x=\"\(n(margin))\" y=\"\(n(authorBaseline))\" font-family=\"\(fonts)\" font-size=\"\(n(authorSize))\" "
                + "letter-spacing=\"\(n(authorSize * 0.16))\" fill=\"\(palette.primary)\" fill-opacity=\"0.86\">\(escape(author))</text>\n"
        }
        // Print-like grain over everything, ink and ground alike.
        out += "<rect width=\"\(n(w))\" height=\"\(n(h))\" fill=\"#000\" filter=\"url(#grain)\" opacity=\"0.5\"/>\n</svg>\n"
        return out
    }

    // MARK: Typography

    struct TitleLayout: Equatable {
        var lines: [String]
        var size: Double
        var lineHeight: Double
    }

    /// Largest size at which the title wraps into few enough lines. There is no text
    /// measurement without AppKit, so widths come from a per-character estimate tuned
    /// for old-style serifs; it errs wide so text never runs off the cover.
    static func layoutTitle(_ title: String, width: Double, coverWidth: Double) -> TitleLayout {
        let steps: [(scale: Double, maxLines: Int)] = [
            (0.132, 3), (0.116, 4), (0.1, 4), (0.088, 5), (0.076, 5), (0.066, 6), (0.056, 7), (0.048, 8),
        ]
        var last = TitleLayout(lines: [title], size: coverWidth * 0.048, lineHeight: coverWidth * 0.048 * 1.12)
        for step in steps {
            let size = (coverWidth * step.scale).rounded()
            let lines = wrap(title, size: size, width: width)
            last = TitleLayout(lines: lines, size: size, lineHeight: (size * 1.1).rounded())
            let fits = lines.allSatisfy { estimatedWidth($0, size: size) <= width }
            if fits, lines.count <= step.maxLines { return last }
        }
        // Still too long at the smallest size: keep what fits and mark the cut.
        if last.lines.count > 8 {
            last.lines = Array(last.lines.prefix(8))
            last.lines[7] = fit(last.lines[7] + " …", size: last.size, tracking: 0, width: width)
        }
        last.lines = last.lines.map { fit($0, size: last.size, tracking: 0, width: width) }
        return last
    }

    /// Greedy wrapping decides how many lines are needed; the words are then spread over
    /// that many lines so the longest is as short as possible. That is what stops a title
    /// ending on a single stranded word.
    static func wrap(_ text: String, size: Double, width: Double) -> [String] {
        let words = text.split(separator: " ").map(String.init)
        guard words.count > 1 else { return words }
        var lineCount = 1
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : current + " " + word
            if current.isEmpty || estimatedWidth(candidate, size: size) <= width {
                current = candidate
            } else {
                lineCount += 1
                current = word
            }
        }
        guard lineCount > 1 else { return [current] }

        func lineWidth(_ from: Int, _ to: Int) -> Double {
            estimatedWidth(words[from..<to].joined(separator: " "), size: size)
        }
        // best[k][i]: smallest possible longest-line width when the first i words fill k lines.
        let count = words.count
        var best = Array(repeating: Array(repeating: Double.infinity, count: count + 1), count: lineCount + 1)
        var split = Array(repeating: Array(repeating: 0, count: count + 1), count: lineCount + 1)
        best[0][0] = 0
        for k in 1...lineCount {
            for i in k...count {
                for j in (k - 1)..<i where best[k - 1][j].isFinite {
                    // Squared widths as a tie-breaker keep the other lines even too.
                    let w = lineWidth(j, i)
                    let cost = max(best[k - 1][j], w) + w * w * 1e-9
                    if cost < best[k][i] {
                        best[k][i] = cost
                        split[k][i] = j
                    }
                }
            }
        }
        var lines: [String] = []
        var end = count
        for k in stride(from: lineCount, to: 0, by: -1) {
            let start = split[k][end]
            lines.insert(words[start..<end].joined(separator: " "), at: 0)
            end = start
        }
        return lines
    }

    static func estimatedWidth(_ text: String, size: Double, tracking: Double = 0) -> Double {
        var total = 0.0
        for character in text {
            let advance: Double
            switch character {
            case "i", "j", "l", "!", ".", ",", ":", ";", "'", "’", "|": advance = 0.3
            case "f", "t", "r", "I", " ", "-", "(", ")", "[", "]": advance = 0.36
            case "m", "w", "M", "W", "—": advance = 0.9
            case _ where character.isUppercase: advance = 0.72
            case _ where character.isNumber: advance = 0.56
            default: advance = 0.53
            }
            total += advance + tracking
        }
        // 0.94: measured against Iowan Old Style and Palatino renders, the table runs wide.
        return total * size * 0.94
    }

    /// Cuts with an ellipsis when a single line cannot fit (author lists, one giant word).
    static func fit(_ text: String, size: Double, tracking: Double, width: Double) -> String {
        guard estimatedWidth(text, size: size, tracking: tracking) > width else { return text }
        var cut = text
        while cut.count > 1, estimatedWidth(cut + "…", size: size, tracking: tracking) > width {
            cut.removeLast()
        }
        return cut.trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: Motifs

    struct Rect {
        var x, y, w, h: Double
        var midY: Double { y + h / 2 }
        var maxY: Double { y + h }
    }

    private static func draw(_ motif: CoverMotif, in r: Rect, margin: Double, palette: CoverPalette, rng: inout SplitMix64) -> String {
        switch motif {
        case .concentricArcs: concentricArcs(r, palette, &rng)
        case .waveInterference: waves(r, palette, &rng)
        case .lattice: lattice(r, margin, palette, &rng)
        case .flowLines: flow(r, palette, &rng)
        case .radialBurst: burst(r, palette, &rng)
        case .network: network(r, margin, palette, &rng)
        }
    }

    /// Rings around an off-centre point, some left open, one filled core in the accent.
    private static func concentricArcs(_ r: Rect, _ palette: CoverPalette, _ rng: inout SplitMix64) -> String {
        let cx = r.w * rng.range(0.52, 0.72)
        // Rings fit the band top to bottom, so they are only ever cut by the cover's own edge.
        let cy = r.y + r.h * rng.range(0.49, 0.51)
        let maxRadius = min(r.h * 0.48, r.w * 0.66)
        let count = 9 + rng.int(5)
        let thin = max(r.w * 0.0035, 0.8)
        let accentRing = 2 + rng.int(count - 3)
        var out = ""
        for i in 1...count {
            let radius = maxRadius * pow(Double(i) / Double(count), 0.88)
            let heavy = rng.unit() < 0.22
            let stroke = i == accentRing ? palette.accent : palette.primary
            let width = i == accentRing ? thin * 3.2 : (heavy ? thin * 2.6 : thin)
            var attributes = "cx=\"\(n(cx))\" cy=\"\(n(cy))\" r=\"\(n(radius))\" stroke=\"\(stroke)\" stroke-width=\"\(n(width))\""
            if rng.unit() < 0.45 {
                // An open ring: one long dash, one gap, turned to a seeded angle.
                let circumference = 2 * Double.pi * radius
                let gap = circumference * rng.range(0.08, 0.3)
                attributes += " stroke-dasharray=\"\(n(circumference - gap)) \(n(gap))\""
                    + " transform=\"rotate(\(n(rng.range(0, 360))) \(n(cx)) \(n(cy)))\""
            }
            out += "<circle \(attributes)/>\n"
        }
        out += "<circle cx=\"\(n(cx))\" cy=\"\(n(cy))\" r=\"\(n(maxRadius / Double(count) * 0.42))\" fill=\"\(palette.accent)\" stroke=\"none\"/>\n"
        return out
    }

    /// Stacked ridgelines: two sinusoids beating inside a moving envelope.
    private static func waves(_ r: Rect, _ palette: CoverPalette, _ rng: inout SplitMix64) -> String {
        let count = 15 + rng.int(6)
        let spacing = r.h * 0.76 / Double(count)
        let top = r.y + r.h * 0.14
        let k1 = 2 * Double.pi / (r.w * rng.range(0.16, 0.26))
        let k2 = k1 * rng.range(1.45, 1.9)
        let p1 = rng.range(0, 6.28), p2 = rng.range(0, 6.28)
        let centre = r.w * rng.range(0.4, 0.62)
        let drift = r.w * rng.range(-0.22, 0.22)
        let sigma = r.w * rng.range(0.2, 0.28)
        let accent = count / 2 + rng.int(3) - 1
        let stroke = max(r.w * 0.004, 0.9)
        var out = ""
        for i in 0..<count {
            let t = Double(i) / Double(count - 1)
            let base = top + Double(i) * spacing
            let c = centre + drift * (t - 0.5) * 2
            // Rows near the middle swing hardest, so the stack swells like a wave packet.
            let amplitude = spacing * (0.5 + 2.6 * sin(t * .pi))
            var points: [(Double, Double)] = []
            var x = -4.0
            while x <= r.w + 4 {
                let envelope = exp(-pow((x - c) / sigma, 2))
                let y = base - amplitude * envelope * (sin(k1 * x + p1 + t * 3.1) + 0.55 * sin(k2 * x + p2 - t * 4.4))
                points.append((x, y))
                x += max(r.w / 220, 1.5)
            }
            let colour = i == accent ? palette.accent : palette.primary
            let width = i == accent ? stroke * 2.2 : stroke
            out += "<path d=\"\(path(points))\" stroke=\"\(colour)\" stroke-width=\"\(n(width))\" stroke-linejoin=\"round\"/>\n"
        }
        return out
    }

    /// A grid of dots whose size ripples outward from a focus; the focus dot is the accent.
    private static func lattice(_ r: Rect, _ margin: Double, _ palette: CoverPalette, _ rng: inout SplitMix64) -> String {
        let columns = 9 + rng.int(4)
        let cell = (r.w - margin * 2) / Double(columns)
        let rows = max(Int((r.h - cell * 0.4) / cell), 2)
        let offsetY = r.y + (r.h - Double(rows) * cell) / 2
        let focusColumn = 1 + rng.int(columns - 2)
        let focusRow = 1 + rng.int(max(rows - 2, 1))
        let wavelength = rng.range(2.4, 3.8)
        let phase = rng.range(0, 1.5)
        var out = "<g stroke=\"none\" fill=\"\(palette.primary)\">\n"
        for row in 0..<rows {
            for column in 0..<columns {
                let dx = Double(column - focusColumn), dy = Double(row - focusRow)
                let distance = (dx * dx + dy * dy).squareRoot()
                let ripple = 0.5 + 0.5 * cos(distance / wavelength * 2 * .pi + phase)
                let falloff = 1 / (1 + distance * 0.09)
                let radius = cell * (0.06 + 0.36 * ripple * falloff)
                let cx = margin + (Double(column) + 0.5) * cell
                let cy = offsetY + (Double(row) + 0.5) * cell
                if column == focusColumn, row == focusRow {
                    out += "<circle cx=\"\(n(cx))\" cy=\"\(n(cy))\" r=\"\(n(cell * 0.44))\" fill=\"\(palette.accent)\"/>\n"
                } else {
                    out += "<circle cx=\"\(n(cx))\" cy=\"\(n(cy))\" r=\"\(n(radius))\"/>\n"
                }
            }
        }
        return out + "</g>\n"
    }

    /// Streamlines of ideal flow past a cylinder; the cylinder itself is the accent.
    private static func flow(_ r: Rect, _ palette: CoverPalette, _ rng: inout SplitMix64) -> String {
        let cx = r.w * rng.range(0.38, 0.66)
        let cy = r.y + r.h * rng.range(0.4, 0.6)
        let radius = min(r.w, r.h) * rng.range(0.13, 0.18)
        let count = 30 + rng.int(8)
        let spacing = r.h / Double(count)
        let stroke = max(r.w * 0.0035, 0.8)
        var out = ""
        for i in 1..<(count - 1) {   // the outermost lines would graze the edge of the band
            // Far upstream the line sits at y0. Along a streamline the stream function
            // psi = y (1 - R²/(x² + y²)) keeps that value, which gives y for each x.
            let y0 = (Double(i) + 0.5) * spacing - (cy - r.y)
            guard abs(y0) > spacing * 0.2 else { continue }
            let side: Double = y0 < 0 ? -1 : 1
            let offset = abs(y0)
            var points: [(Double, Double)] = []
            var x = -6.0
            while x <= r.w + 6 {
                let dx = x - cx
                // psi(y) - offset is negative on the cylinder (or at y = offset) and positive
                // at offset + R, with one root between: bisect for it.
                var low = max(offset, max(radius * radius - dx * dx, 0).squareRoot())
                var high = offset + radius
                for _ in 0..<40 {
                    let mid = (low + high) / 2
                    let psi = mid * (1 - radius * radius / (dx * dx + mid * mid))
                    if psi < offset { low = mid } else { high = mid }
                }
                points.append((x, cy + side * (low + high) / 2))
                x += max(r.w / 200, 1.5)
            }
            out += "<path d=\"\(path(points))\" stroke-width=\"\(n(stroke))\" stroke-linejoin=\"round\"/>\n"
        }
        out += "<circle cx=\"\(n(cx))\" cy=\"\(n(cy))\" r=\"\(n(radius * 0.62))\" fill=\"\(palette.accent)\" stroke=\"none\"/>\n"
        return out
    }

    /// Rays of uneven length from one point.
    private static func burst(_ r: Rect, _ palette: CoverPalette, _ rng: inout SplitMix64) -> String {
        let cx = r.w * rng.range(0.36, 0.64)
        let cy = r.y + r.h * rng.range(0.44, 0.58)
        let count = 96 + rng.int(48)
        let inner = min(r.w, r.h) * 0.075
        let reach = min(r.h * 0.5, r.w * 0.56)
        let lobes = Double(3 + rng.int(4))
        let p1 = rng.range(0, 6.28), p2 = rng.range(0, 6.28)
        let stroke = max(r.w * 0.0032, 0.8)
        var out = ""
        for i in 0..<count {
            let angle = Double(i) / Double(count) * 2 * .pi
            let shape = 0.5 + 0.28 * sin(angle * lobes + p1) + 0.22 * sin(angle * (lobes * 2 + 1) + p2)
            let length = inner + reach * max(0.16, shape) * rng.range(0.8, 1.0)
            let x1 = cx + cos(angle) * inner, y1 = cy + sin(angle) * inner
            let x2 = cx + cos(angle) * length, y2 = cy + sin(angle) * length
            out += "<line x1=\"\(n(x1))\" y1=\"\(n(y1))\" x2=\"\(n(x2))\" y2=\"\(n(y2))\" stroke-width=\"\(n(stroke))\"/>\n"
        }
        out += "<circle cx=\"\(n(cx))\" cy=\"\(n(cy))\" r=\"\(n(inner * 0.56))\" fill=\"\(palette.accent)\" stroke=\"none\"/>\n"
        return out
    }

    /// Two rows of points, every pair joined, weights shown as line strength: one strong
    /// path in the accent.
    private static func network(_ r: Rect, _ margin: Double, _ palette: CoverPalette, _ rng: inout SplitMix64) -> String {
        let count = 6 + rng.int(3)
        let top = r.y + r.h * 0.16, bottom = r.y + r.h * 0.84
        let step = (r.w - margin * 2) / Double(count - 1)
        let xs = (0..<count).map { margin + Double($0) * step }
        let dot = max(r.w * 0.011, 2)
        let from = rng.int(count)
        var to = rng.int(count)
        if abs(to - from) < 2 { to = (from + count / 2) % count }
        var out = ""
        for a in 0..<count {
            for b in 0..<count where !(a == from && b == to) {
                // Mostly faint, a few strong: squaring pushes weights toward zero.
                let weight = pow(rng.unit(), 2.2)
                out += "<line x1=\"\(n(xs[a]))\" y1=\"\(n(top))\" x2=\"\(n(xs[b]))\" y2=\"\(n(bottom))\" "
                    + "stroke-width=\"\(n(max(r.w * 0.0028, 0.7)))\" stroke-opacity=\"\(n(0.1 + 0.75 * weight))\"/>\n"
            }
        }
        out += "<line x1=\"\(n(xs[from]))\" y1=\"\(n(top))\" x2=\"\(n(xs[to]))\" y2=\"\(n(bottom))\" "
            + "stroke=\"\(palette.accent)\" stroke-width=\"\(n(max(r.w * 0.008, 1.6)))\"/>\n"
        for (index, x) in xs.enumerated() {
            let topFill = index == from ? palette.accent : palette.primary
            let bottomFill = index == to ? palette.accent : palette.primary
            out += "<circle cx=\"\(n(x))\" cy=\"\(n(top))\" r=\"\(n(dot))\" fill=\"\(topFill)\" stroke=\"none\"/>\n"
            out += "<circle cx=\"\(n(x))\" cy=\"\(n(bottom))\" r=\"\(n(dot))\" fill=\"\(bottomFill)\" stroke=\"none\"/>\n"
        }
        return out
    }

    // MARK: Output helpers

    private static func path(_ points: [(Double, Double)]) -> String {
        var d = ""
        for (index, point) in points.enumerated() {
            d += (index == 0 ? "M" : "L") + n(point.0) + " " + n(point.1)
        }
        return d
    }

    /// One decimal, no trailing ".0", and a fixed locale: SVG wants "." decimals everywhere.
    private static func n(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), rounded)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
