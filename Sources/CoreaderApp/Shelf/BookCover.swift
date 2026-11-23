import AppKit
import CoreaderKit
import ImageIO
import SwiftUI

/// Decoded, downsampled cover images. Covers are large files; the shelf needs thumbnails.
@MainActor
final class CoverCache {
    static let shared = CoverCache()
    private let cache = NSCache<NSString, NSImage>()

    private static func key(_ url: URL, _ version: Int, _ maxPixel: Int) -> NSString {
        "\(url.path)#\(version)#\(maxPixel)" as NSString
    }

    /// Already decoded? Answered at once, so a cell scrolling back into view shows its
    /// cover in the same frame and never flashes the placeholder.
    func cached(for url: URL, version: Int, maxPixel: Int) -> NSImage? {
        cache.object(forKey: Self.key(url, version, maxPixel))
    }

    func image(for url: URL, version: Int, maxPixel: Int) async -> NSImage? {
        let key = Self.key(url, version, maxPixel)
        if let hit = cache.object(forKey: key) { return hit }
        let image: NSImage? = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailWithTransform: true,
                // Decode now, on this thread; otherwise the first draw does it on the main one.
                kCGImageSourceShouldCacheImmediately: true,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

/// A book cover that reads as an object: soft edge light along the spine, a grounded
/// shadow. The cover keeps its own proportions and is never cropped: publishers' covers
/// and PDF first pages are often wider than the 2:3 this app draws.
struct BookCover: View {
    let entry: BookEntry
    /// Width of a 2:3 cover; the height of every cover is one and a half times this.
    var width: CGFloat = 150
    /// On the shelf a wider cover takes the extra width it needs (up to `growth` times
    /// `width`) and keeps the full height. Elsewhere it is fitted inside `width`.
    var grows = false
    /// Told the width the cover is drawn at, so a caller can line text up under it.
    var onWidth: ((CGFloat) -> Void)?

    static let growth: CGFloat = 1.24

    /// The size a cover of this shape is drawn at: as large as fits the space it may use.
    static func drawnSize(aspect: CGFloat, width: CGFloat, grows: Bool) -> CGSize {
        let height = width * 1.5, limit = grows ? width * growth : width
        // Odd shapes (a strip, a banner) are held to something that still reads as a cover.
        let aspect = min(max(aspect.isFinite ? aspect : 2.0 / 3.0, 0.45), 1.6)
        let fitted = height * aspect
        return fitted <= limit ? CGSize(width: fitted, height: height) : CGSize(width: limit, height: limit / aspect)
    }
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var image: NSImage?

    @Environment(\.displayScale) private var displayScale

    private var version: Int { app.coverVersion[entry.id] ?? 0 }
    /// Decoded at the size it is drawn (the taller side, in pixels), so nothing is
    /// resampled while scrolling.
    private var maxPixel: Int { Int((width * 1.5 * displayScale).rounded(.up)) }

    var body: some View {
        let corner = max(2, width * 0.018)
        let shown = image ?? entry.coverURL.flatMap { CoverCache.shared.cached(for: $0, version: version, maxPixel: maxPixel) }
        let aspect = shown.flatMap { $0.size.height > 0 ? $0.size.width / $0.size.height : nil } ?? 2.0 / 3.0
        let size = Self.drawnSize(aspect: aspect, width: width, grows: grows)
        return cover(shown, size: size, corner: corner)
            // The space it stands in: full height always, so a row of covers shares a
            // baseline; a fitted cover is centred in its 2:3 slot, a grown one sets its own width.
            .frame(width: grows ? size.width : width, height: width * 1.5, alignment: .bottom)
            .onChange(of: size.width, initial: true) { onWidth?(size.width) }
    }

    private func cover(_ shown: NSImage?, size: CGSize, corner: CGFloat) -> some View {
        ZStack {
            if let shown {
                Image(nsImage: shown)
                    .resizable()
            } else {
                PlaceholderCover(book: entry.book)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .leading) {
            // Hinge: a dark crease beside a thin highlight, as on a bound book. Plain
            // alpha, not a blend mode: a blend makes every cover its own offscreen pass.
            LinearGradient(stops: [
                .init(color: .black.opacity(0.20), location: 0),
                .init(color: .white.opacity(0.14), location: 0.45),
                .init(color: .black.opacity(0.08), location: 0.75),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
            .frame(width: max(5, width * 0.055))
        }
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.black.opacity(0.10), lineWidth: 0.5)
        }
        // The shadow belongs to a plain shape behind the cover: cheap to draw, where a
        // shadow on the picture itself is blurred from the picture's pixels every time.
        .background {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(.black.opacity(0.9))
                .shadow(color: .black.opacity(0.24), radius: width * 0.06, x: 0, y: width * 0.045)
        }
        .task(id: "\(entry.book.coverFile ?? "")#\(version)") {
            guard let url = entry.coverURL else { image = nil; return }
            image = await CoverCache.shared.image(for: url, version: version, maxPixel: maxPixel)
        }
        .accessibilityLabel("Cover of \(entry.book.title)")
    }
}

/// Shown for the moment before a cover exists: cloth-coloured board with the title.
struct PlaceholderCover: View {
    let book: Book

    private var ground: Color {
        let grounds: [UInt32] = [0x3C4A3E, 0x5A2E2A, 0x2F3E52, 0x6B5A3A, 0x44384F, 0x2E4A4A, 0x7A4A2C]
        let seed = book.title.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hex: grounds[seed % grounds.count])
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ground
                VStack(alignment: .leading, spacing: geo.size.width * 0.04) {
                    Text(book.title)
                        .font(.system(size: geo.size.width * 0.105, weight: .medium, design: .serif))
                        .foregroundStyle(Color(hex: 0xF3EAD8))
                        .lineLimit(6)
                        .minimumScaleFactor(0.6)
                    Rectangle().fill(Color(hex: 0xD9B36C)).frame(width: geo.size.width * 0.18, height: 1)
                    Spacer()
                    Text(book.authorLine)
                        .font(.system(size: geo.size.width * 0.065, weight: .regular, design: .serif))
                        .foregroundStyle(Color(hex: 0xF3EAD8).opacity(0.8))
                        .lineLimit(2)
                }
                .padding(geo.size.width * 0.11)
            }
        }
    }
}

/// The rating as one drawing, laid out exactly like `StarRating`, with nothing to click.
struct StarPicture: View {
    var rating: Int
    var size: CGFloat = 12
    @Environment(\.palette) private var palette

    var body: some View {
        let step = size * 1.3
        let gold = Color(hex: 0xD99A2B), empty = palette.tertiary.opacity(0.7)
        Canvas { context, canvas in
            for star in 1...5 {
                let symbol = context.resolve(Text(Image(systemName: star <= rating ? "star.fill" : "star"))
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(star <= rating ? gold : empty))
                let width = symbol.measure(in: canvas).width
                context.draw(symbol, at: CGPoint(x: step * Double(star - 1) + width / 2, y: canvas.height / 2))
            }
        }
        .frame(width: step * 5, height: size * 1.4)
        .contentShape(Rectangle())
    }
}

struct StarRating: View {
    var rating: Int?
    var size: CGFloat = 12
    var onChange: ((Int?) -> Void)?
    @Environment(\.palette) private var palette
    @State private var hover: Int?

    var body: some View {
        let shown = hover ?? rating ?? 0
        let step = size * 1.3   // one star plus the gap after it
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    // Clicking the current rating clears it.
                    onChange?(rating == star ? nil : star)
                } label: {
                    Image(systemName: star <= shown ? "star.fill" : "star")
                        .font(.system(size: size, weight: .medium))
                        .foregroundStyle(star <= shown ? Color(hex: 0xD99A2B) : palette.tertiary.opacity(0.7))
                        .frame(width: step, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .allowsHitTesting(onChange != nil)
        // One hover tracker for the row, not one per star: a shelf holds this view once
        // per book, and five trackers each was the costliest part of a cell.
        .onContinuousHover { phase in
            if case .active(let point) = phase { hover = min(5, max(1, Int(point.x / step) + 1)) } else { hover = nil }
        }
        .accessibilityElement()
        .accessibilityLabel(rating.map { "\($0) of 5 stars" } ?? "Not rated")
        .accessibilityAdjustableAction { direction in
            guard let onChange else { return }
            let current = rating ?? 0
            onChange(direction == .increment ? min(5, current + 1) : (current <= 1 ? nil : current - 1))
        }
    }
}
