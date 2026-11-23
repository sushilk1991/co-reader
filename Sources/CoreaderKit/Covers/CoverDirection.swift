import Foundation

/// The art direction of a generated cover. One house style on every cover made a shelf of
/// papers look like one book printed twenty times, so each title draws a direction, a
/// layout and a palette separately; a new variant draws again.
public enum CoverDirection: String, Sendable, CaseIterable {
    case diagram, engraving, cutPaper, linocut, typographic, swissPoster, isometric, alteredObject, chart, pattern, overprint, constructivist

    public static func direction(for brief: CoverBrief) -> CoverDirection {
        // Shifted so direction, layout, palette and motif do not move together.
        allCases[Int((brief.seed >> 29) % UInt64(allCases.count))]
    }

    /// How the picture is made. Each names a tradition the image model knows, then says
    /// what that means in marks on the page.
    var artwork: String {
        switch self {
        case .diagram:
            "an abstract mathematical diagram drawn large, in the manner of Stripe Press hardcovers and mid-century "
                + "scientific book jackets: dozens of precise fine lines against a few heavy confident strokes"
        case .engraving:
            "a single subject rendered as a fine-line engraved plate from a nineteenth-century scientific atlas: "
                + "cross-hatching, stippling, hairline contours, printed in one ink, large on the page"
        case .cutPaper:
            "three to five bold cut-paper shapes with slightly uneven scissor edges, overlapping like a Matisse cut-out "
                + "or a 1960s Pelican paperback by Germano Facetti's studio; flat colour, no outlines"
        case .linocut:
            "a linocut print: thick carved shapes, visible gouge marks and chatter in the cleared areas, slightly "
                + "uneven ink coverage, one strong image cut in two colours"
        case .typographic:
            "no picture at all: the title itself is the artwork, in the manner of David Pearson's Penguin Great Ideas "
                + "covers. Letterforms set very large and arranged so that their arrangement acts out the idea, with "
                + "printer's rules, ornaments or a border as the only decoration"
        case .swissPoster:
            "one very large simple geometric form on a strict grid, in the Swiss International Style of Josef "
                + "Müller-Brockmann and Armin Hofmann: extreme scale contrast, generous empty space, mathematical placement"
        case .isometric:
            "an isometric technical drawing of an imagined machine, building or apparatus that embodies the idea, "
                + "with engineering line weights and a few flat fills, like a plate from a patent or an architect's axonometric"
        case .alteredObject:
            "one ordinary recognisable object, changed in a single surprising way that states the idea as a visual pun, "
                + "painted in flat gouache in the manner of Paul Rand and Alvin Lustig's mid-century jackets"
        case .chart:
            "an imagined map, star chart or geological cross-section of the idea: contour lines, soundings, "
                + "meridians and small survey marks, with no labels, drawn like an old hydrographic chart"
        case .pattern:
            "a repeating pattern of one small drawn unit that tiles the cover like a 1930s patterned paper binding, "
                + "in which exactly one unit breaks the rule, and that exception is the idea"
        case .overprint:
            "a two-colour risograph print: two big silhouetted shapes overprinting to make a third colour where they "
                + "cross, coarse halftone dots, slight misregistration, heavy paper grain"
        case .constructivist:
            "hard diagonals, wedges, bars and circles thrusting across the page in the manner of El Lissitzky and "
                + "1920s constructivist posters, with flat colour, strong asymmetry and no ornament"
        }
    }

    var typeface: String {
        switch self {
        case .diagram, .engraving, .chart: "an elegant high-contrast serif"
        case .cutPaper, .alteredObject: "a warm geometric sans-serif with round letterforms"
        case .linocut: "a sturdy slab serif that looks hand-cut"
        case .typographic: "a mix of at most two typefaces chosen for character, such as a fat-face display serif with small capitals"
        case .swissPoster, .isometric: "a neutral grotesque sans-serif, tightly set"
        case .pattern: "a classical book serif in small capitals"
        case .overprint: "a bold condensed sans-serif"
        case .constructivist: "a heavy condensed sans-serif in capitals"
        }
    }
}

/// Where the title sits and how much of the cover it takes.
public enum CoverLayout: String, Sendable, CaseIterable {
    case titleTop, titleBottom, titleBand, titleHuge, titleLabel, titleCorner

    public static func layout(for brief: CoverBrief) -> CoverLayout {
        allCases[Int((brief.seed >> 41) % UInt64(allCases.count))]
    }

    var prompt: String {
        switch self {
        case .titleTop:
            "The title sits in the upper third, aligned left, large, over calm ground; the artwork takes the rest and bleeds off the bottom."
        case .titleBottom:
            "The artwork fills the upper two thirds and bleeds off the top and sides; the title sits in the lower third, aligned left, over calm ground."
        case .titleBand:
            "The artwork runs the full height of the cover; the title sits in a solid horizontal band of flat colour across the middle."
        case .titleHuge:
            "The title is set enormous, filling most of the width in stacked lines, and the artwork threads behind and between the lines."
        case .titleLabel:
            "The artwork fills the whole cover edge to edge; the title sits small and centred in a plain rectangular label, like a specimen label, in the upper half."
        case .titleCorner:
            "The artwork is one big shape placed off-centre and cropped by two edges; the title is set small in the opposite corner, with wide empty margins."
        }
    }
}
