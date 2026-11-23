import Foundation

/// What a cover is made from. `summary` is what lets the artwork say something about the
/// work; without it the motif falls back to a seeded choice.
public struct CoverBrief: Sendable, Equatable {
    public var title: String
    public var authors: [String]
    public var summary: String?
    public var kind: BookKind
    /// 0 for a title's first cover. Asking for a new design raises it, which changes the
    /// palette, the motif and the geometry while staying repeatable.
    public var variant: Int

    public init(title: String, authors: [String] = [], summary: String? = nil, kind: BookKind = .book, variant: Int = 0) {
        self.title = title
        self.authors = authors
        self.summary = summary
        self.kind = kind
        self.variant = variant
    }

    public init(book: Book) {
        self.init(title: book.title, authors: book.authors, summary: book.summary, kind: book.kind, variant: book.coverVariant ?? 0)
    }

    /// The title as set on a cover: whitespace collapsed, and a long "Main: subtitle"
    /// title cut to its main part, because both image models and a narrow cover handle
    /// a dozen words far better than thirty.
    public var displayTitle: String {
        let collapsed = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard collapsed.count > 70 else { return collapsed.isEmpty ? "Untitled" : collapsed }
        for separator in [": ", " — ", " – ", " - "] {
            if let range = collapsed.range(of: separator) {
                let head = String(collapsed[..<range.lowerBound])
                if head.count >= 12 { return head }
            }
        }
        return collapsed
    }

    /// "Ada Lovelace", "A. Author & B. Author", or "First Author et al."
    public var authorLine: String? {
        let names = authors
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
        switch names.count {
        case 0: return nil
        case 1: return names[0]
        case 2: return "\(names[0]) & \(names[1])"
        default: return "\(names[0]) et al."
        }
    }

    var seed: UInt64 { FNV1a.hash(displayTitle.lowercased() + (variant == 0 ? "" : "#\(variant)")) }
}

/// Ground plus two inks. Both the AI prompt and the procedural cover draw from this one
/// set, so a shelf of generated covers reads as a family.
public struct CoverPalette: Sendable, Equatable {
    public var name: String
    /// Solid background.
    public var ground: String
    /// Main ink: most of the artwork and the title.
    public var primary: String
    /// Used once or twice, for the element the eye should land on.
    public var accent: String
    /// Plain-language description for the image prompt.
    public var description: String

    public static let all: [CoverPalette] = [
        CoverPalette(name: "oxblood", ground: "#5A1A1F", primary: "#EADCC0", accent: "#E08A3C",
                     description: "deep oxblood red ground, warm bone-white ink, one burnt-orange accent"),
        CoverPalette(name: "midnight", ground: "#14213D", primary: "#F1E8D8", accent: "#E5A823",
                     description: "deep midnight navy ground, cream ink, one marigold-yellow accent"),
        CoverPalette(name: "forest", ground: "#1E3B2F", primary: "#EBE0C8", accent: "#E0704C",
                     description: "deep forest green ground, ivory ink, one coral accent"),
        CoverPalette(name: "ink", ground: "#17171B", primary: "#EDE6D6", accent: "#E4572E",
                     description: "near-black ink ground, off-white ink, one vermilion accent"),
        CoverPalette(name: "ochre", ground: "#D19A2E", primary: "#1E1B16", accent: "#F7EFDD",
                     description: "rich mustard-ochre ground, black ink, one cream accent"),
        CoverPalette(name: "bone", ground: "#EEE6D4", primary: "#1C2A4E", accent: "#C8402E",
                     description: "warm bone-paper ground, deep ink-blue ink, one signal-red accent"),
        CoverPalette(name: "teal", ground: "#0F4A49", primary: "#F0E6D2", accent: "#F2B544",
                     description: "deep teal ground, cream ink, one golden-yellow accent"),
        CoverPalette(name: "plum", ground: "#3B1F41", primary: "#EBDDC9", accent: "#E07A5F",
                     description: "dark aubergine-plum ground, pale cream ink, one terracotta accent"),
        CoverPalette(name: "terracotta", ground: "#B4472F", primary: "#F5ECDD", accent: "#1F2A44",
                     description: "terracotta-red ground, cream ink, one deep navy accent"),
        CoverPalette(name: "slate", ground: "#2D3945", primary: "#E9E2D0", accent: "#7FC8A9",
                     description: "blue-slate ground, parchment ink, one pale mint accent"),
        // Light and bright grounds: without them a shelf of generated covers is a wall of dark.
        CoverPalette(name: "tangerine", ground: "#EE7A2E", primary: "#1B1A17", accent: "#FBF3E4",
                     description: "bright paperback-orange ground, black ink, one cream accent"),
        CoverPalette(name: "sky", ground: "#BFD9E6", primary: "#152238", accent: "#D8432B",
                     description: "pale sky-blue ground, deep navy ink, one poppy-red accent"),
        CoverPalette(name: "rose", ground: "#F0C4C0", primary: "#3A1420", accent: "#1F6F5C",
                     description: "dusty rose-pink ground, dark wine ink, one bottle-green accent"),
        CoverPalette(name: "chalk", ground: "#F7F4EC", primary: "#111111", accent: "#1F4FD8",
                     description: "chalk-white ground, black ink, one ultramarine-blue accent"),
        CoverPalette(name: "sage", ground: "#C9D5B5", primary: "#1F2D1E", accent: "#C4472B",
                     description: "soft sage-green ground, dark pine ink, one brick-red accent"),
        CoverPalette(name: "lemon", ground: "#F2D94E", primary: "#1A1A1A", accent: "#D23C2A",
                     description: "acid lemon-yellow ground, black ink, one tomato-red accent"),
        CoverPalette(name: "cobalt", ground: "#1F3FB3", primary: "#F5F0E3", accent: "#F2C230",
                     description: "saturated cobalt-blue ground, cream ink, one sunflower-yellow accent"),
    ]

    /// Same title and variant, same palette, every time.
    public static func palette(for brief: CoverBrief) -> CoverPalette {
        all[Int(brief.seed % UInt64(all.count))]
    }
}

/// Families of abstract geometry. The title's seed picks one; subject keywords only
/// weight the draw (waves are likelier for anything spectral). A hard rule put the same
/// artwork on every paper in a library about one field.
public enum CoverMotif: String, Sendable, CaseIterable {
    case concentricArcs, waveInterference, lattice, flowLines, radialBurst, network

    public static func motif(for brief: CoverBrief) -> CoverMotif {
        let hits = hits(in: brief)
        let best = hits.values.max() ?? 0
        // The best-matching family gets two tickets in the draw, every other family one.
        let tickets = allCases.flatMap { motif in
            Array(repeating: motif, count: best > 0 && hits[motif] == best ? 2 : 1)
        }
        // Shifted so palette and motif are not locked to each other.
        return tickets[Int((brief.seed >> 17) % UInt64(tickets.count))]
    }

    private static let keywords: [(CoverMotif, [String])] = [
        (.waveInterference, ["fourier", "wave", "signal", "frequency", "spectrum", "spectral", "audio", "speech",
                             "sound", "music", "oscillat", "harmonic", "quantum", "interference", "time series"]),
        (.network, ["attention", "transformer", "neural", "network", "graph", "social", "connection", "language model",
                    "deep learning", "internet", "distributed", "protocol"]),
        (.lattice, ["crystal", "lattice", "grid", "matrix", "tensor", "database", "discrete", "cellular", "pixel",
                    "image recognition", "convolution", "combinator", "bureaucra", "institution"]),
        (.flowLines, ["flow", "fluid", "diffusion", "gradient", "optimi", "dynamics", "river", "evolution", "climate",
                      "turbulen", "economy", "market", "trade", "history"]),
        (.radialBurst, ["energy", "light", "sun", "star", "explosion", "big bang", "radiation", "growth", "innovation",
                        "revolution", "discovery", "invention"]),
        (.concentricArcs, ["orbit", "planet", "gravity", "cosmos", "time", "memory", "cycle", "ripple", "recursion",
                           "self", "mind", "conscious", "focus", "depth"]),
    ]

    static func hits(in brief: CoverBrief) -> [CoverMotif: Int] {
        let text = (brief.title + " " + (brief.summary ?? "")).lowercased()
        let words = Set(text.split(whereSeparator: { !$0.isLetter }).map(String.init))
        var found: [CoverMotif: Int] = [:]
        for (motif, keys) in keywords {
            // Whole words or word prefixes ("optimi" matches "optimisation"), never the
            // middle of a word: "sun" must not fire on "misunderstood".
            let hits = keys.reduce(0) { count, key in
                let hit = key.contains(" ") ? text.contains(key) : words.contains { $0.hasPrefix(key) }
                return count + (hit ? 1 : 0)
            }
            if hits > 0 { found[motif] = hits }
        }
        return found
    }

    /// How to describe the family to an image model: a starting point, not a recipe.
    var promptHint: String {
        switch self {
        case .concentricArcs: "concentric rings or arcs, slightly off-centre, a few of them broken or offset"
        case .waveInterference: "layered sinusoidal waves or a spectrum of stacked ridgelines interfering with each other"
        case .lattice: "a precise lattice or grid of repeated marks that deforms or changes scale across the page"
        case .flowLines: "many fine parallel streamlines bending around an invisible obstacle, like a flow field"
        case .radialBurst: "fine lines radiating from a single point, uneven in length, like a burst or a sun diagram"
        case .network: "many points joined by a dense fan of straight or arcing lines of varying weight, one path picked out"
        }
    }
}
