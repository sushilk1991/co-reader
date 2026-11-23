import Foundation

/// Folder and file names: ASCII, lowercase, hyphen-separated, so they survive every
/// file system, sync service and shell an agent might use.
public enum Slug {
    public static func make(_ text: String, fallback: String = "untitled", maxLength: Int = 60) -> String {
        // ICU: transliterate any script to Latin, then to plain ASCII (ß → ss, é → e).
        let ascii = text.applyingTransform(StringTransform(rawValue: "Any-Latin; Latin-ASCII; Lower"), reverse: false)
            ?? text.lowercased()
        var slug = ""
        var gap = false
        for scalar in ascii.unicodeScalars {
            switch scalar {
            case "a"..."z", "0"..."9":
                if gap, !slug.isEmpty { slug.append("-") }
                gap = false
                slug.unicodeScalars.append(scalar)
            case "'", "\u{2019}", "\u{02BC}":
                continue // "don't" reads better as "dont" than "don-t"
            default:
                gap = true
            }
        }
        if slug.count > maxLength {
            var cut = String(slug.prefix(maxLength))
            // Prefer ending on a whole word when that does not throw away most of the name.
            if slug[slug.index(slug.startIndex, offsetBy: maxLength)] != "-",
               let hyphen = cut.lastIndex(of: "-"),
               cut.distance(from: cut.startIndex, to: hyphen) >= maxLength / 2 {
                cut = String(cut[..<hyphen])
            }
            while cut.hasSuffix("-") { cut.removeLast() }
            slug = cut
        }
        return slug.isEmpty ? fallback : slug
    }
}
