import Foundation

public enum CoverPromptBuilder {
    /// Portrait 2:3, the size both backends are asked for.
    public static let imageWidth = 1024
    public static let imageHeight = 1536

    /// A complete image-generation prompt. Deterministic: the same brief always yields
    /// the same text. A new design is asked for by raising `brief.variant`.
    ///
    /// The prompt asks for an idea before it asks for a picture. Told only "an abstract
    /// motif for this subject", an image model draws the same web of dots and curves for
    /// every machine-learning paper; told to find what this one work claims and to show
    /// that, in a named tradition of cover design, it has something to say.
    public static func prompt(for brief: CoverBrief) -> String {
        let palette = CoverPalette.palette(for: brief)
        let direction = CoverDirection.direction(for: brief)
        let layout = CoverLayout.layout(for: brief)
        let title = quotable(brief.displayTitle)
        let author = brief.authorLine.map(quotable)

        var lines: [String] = []
        lines.append(
            "Design the front cover of a \(noun(for: brief.kind)). Hold it to the standard of the best trade publishing: "
                + "Penguin Great Ideas, Pelican paperbacks, Faber, Fitzcarraldo, Stripe Press. Be more ambitious than a "
                + "tasteful pattern: this should be a cover a designer would put in a portfolio, and one that could "
                + "belong to no other work."
        )
        lines.append("Format: flat, front-facing cover artwork that fills the whole frame edge to edge, portrait, 2:3 aspect ratio.")

        var subject = "The work is titled \"\(title)\"."
        if let summary = brief.summary?.split(whereSeparator: \.isWhitespace).joined(separator: " "), !summary.isEmpty {
            subject += " What it says: \(String(summary.prefix(900)))"
        }
        lines.append(subject)

        lines.append(
            "Concept first: before drawing, work out the one claim, mechanism or surprise that sets this work apart "
                + "from others in its field, and find a concrete visual metaphor for it, something a reader would "
                + "recognise with a smile after reading the work. Show that one idea and nothing else. Things from the "
                + "world are welcome when they carry the idea: tools, instruments, animals, plants, buildings, "
                + "landscapes, hands, stylised figures. A cover that would suit any work on the same topic is a failure. "
                + "Avoid the stock imagery of the field: no robots, no glowing brains, no circuit boards, no binary "
                + "digits, no generic web of dots joined by lines, no photorealism."
        )

        var artwork = "Art direction: \(direction.artwork)."
        if direction == .diagram {
            artwork += " A possible starting point: \(CoverMotif.motif(for: brief).promptHint)."
        }
        artwork += " Commit to this manner fully, at poster scale: one image, big, confident and simple enough to read "
            + "from across a room, never a small picture floating in empty space."
        lines.append(artwork)

        if direction != .typographic { lines.append("Layout: \(layout.prompt)") }

        lines.append(
            "Colour: strictly limited palette, \(palette.description) "
                + "(ground \(palette.ground), ink \(palette.primary), accent \(palette.accent)). "
                + "Flat colour only; tints of these three are allowed. No gradients, no glow, no 3D rendering, no drop shadows. "
                + "The accent is used sparingly, on the element the eye should land on."
        )
        lines.append(
            "Finish: looks printed on uncoated paper, with a faint paper grain and slightly soft ink edges. "
                + "Matte and tactile."
        )

        var typography = "Typography: the title \"\(title)\" set exactly as written, spelled correctly, in "
            + "\(direction.typeface), in the ink colour, with clean margins, broken over as many lines as it needs."
        if let author {
            typography += " The author line \"\(author)\" set small in letterspaced capitals near the bottom edge."
        }
        typography += " No other text of any kind: no subtitle, no tagline, no publisher name, no logo, no barcode, no numbers, no signature."
        lines.append(typography)

        lines.append(
            "Do not show a physical book, a mockup, a spine, pages, a table, hands holding it or a background behind the cover. "
                + "The image is the cover itself, perfectly flat and straight-on, with no border and no perspective."
        )
        return lines.joined(separator: "\n")
    }

    private static func noun(for kind: BookKind) -> String {
        switch kind {
        case .book: "non-fiction book"
        case .paper: "research paper, treated as if it were a small serious book"
        case .article: "long-form essay, treated as if it were a small serious book"
        }
    }

    /// The prompt quotes the title, so quotes inside it would end the quotation early.
    private static func quotable(_ text: String) -> String {
        text.replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\u{201C}", with: "'")
            .replacingOccurrences(of: "\u{201D}", with: "'")
    }
}
