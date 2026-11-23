import Foundation

public enum CoverPromptBuilder {
    /// Portrait 2:3, the size both backends are asked for.
    public static let imageWidth = 1024
    public static let imageHeight = 1536

    /// A complete image-generation prompt. Deterministic: the same brief always yields
    /// the same text. A new design is asked for by raising `brief.variant`.
    public static func prompt(for brief: CoverBrief) -> String {
        let palette = CoverPalette.palette(for: brief)
        let motif = CoverMotif.motif(for: brief)
        let title = quotable(brief.displayTitle)
        let author = brief.authorLine.map(quotable)

        var lines: [String] = []
        lines.append(
            "Front cover artwork for a \(noun(for: brief.kind)), designed in the spirit of Stripe Press hardcovers "
                + "and mid-century scientific book jackets: one bold abstract idea, drawn large."
        )
        lines.append("Format: flat, front-facing cover artwork that fills the whole frame edge to edge, portrait, 2:3 aspect ratio.")

        var subject = "Subject: the work is titled \"\(title)\"."
        if let summary = brief.summary?.split(whereSeparator: \.isWhitespace).joined(separator: " "), !summary.isEmpty {
            subject += " It is about: \(String(summary.prefix(600)))"
        }
        lines.append(subject)

        lines.append(
            "Artwork: a single abstract geometric or mathematical motif that captures the essence of that subject, "
                + "the way a diagram in a beautiful textbook would. A good starting point: \(motif.promptHint). "
                + "Prefer the visual idea that belongs to this subject over a generic pattern. "
                + "No literal illustration, no people, no faces, no objects, no robots, no brains, no glowing circuitry. "
                + "Scale: the motif is the hero, at poster scale. It is big and graphic, runs edge to edge, fills the "
                + "whole lower 55% of the cover and bleeds off the bottom and one side. Dozens of elements, not a handful; "
                + "mix a few heavy confident strokes or solid flat shapes with fine precise lines. "
                + "Never a small diagram floating in the middle of empty space. "
                + "The upper part behind the title stays empty solid ground."
        )
        lines.append(
            "Colour: strictly limited palette, \(palette.description) "
                + "(ground \(palette.ground), ink \(palette.primary), accent \(palette.accent)). "
                + "One rich solid ground colour, no gradients, no glow, no 3D, no drop shadows. "
                + "The accent appears once, on the single element the eye should land on."
        )
        lines.append(
            "Finish: looks offset-printed on uncoated paper, with a faint paper grain and slightly soft ink edges. "
                + "Matte and tactile."
        )

        var typography = "Typography: the title \"\(title)\" set exactly as written, spelled correctly, in an elegant "
            + "high-contrast serif, in the ink colour, large and well spaced, aligned left in the upper part of the cover, "
            + "broken over two to four lines with clean margins."
        if let author {
            typography += " The author line \"\(author)\" set small in letterspaced capitals near the bottom edge."
        }
        typography += " No other text of any kind: no subtitle, no tagline, no publisher name, no logo, no barcode, no numbers, no signature."
        lines.append(typography)

        lines.append(
            "Do not show a physical book, a mockup, a spine, pages, a table, hands or a background behind the cover. "
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
