import AppKit
import CoreaderKit
import ImageIO
import SwiftUI

/// Decoded, downsampled cover images. Covers are large files; the shelf needs thumbnails.
@MainActor
final class CoverCache {
    static let shared = CoverCache()
    private let cache = NSCache<NSString, NSImage>()

    func image(for url: URL, version: Int, maxPixel: Int) async -> NSImage? {
        let key = "\(url.path)#\(version)#\(maxPixel)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let image: NSImage? = await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailWithTransform: true,
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }.value
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

/// A book cover that reads as an object: fixed 2:3 board, soft edge light along the spine,
/// a grounded shadow.
struct BookCover: View {
    let entry: BookEntry
    var width: CGFloat = 150
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var image: NSImage?

    private var version: Int { app.coverVersion[entry.id] ?? 0 }

    var body: some View {
        let height = width * 1.5
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                PlaceholderCover(book: entry.book)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: max(2, width * 0.018), style: .continuous))
        .overlay(alignment: .leading) {
            // Hinge: a dark crease beside a thin highlight, as on a bound book.
            LinearGradient(stops: [
                .init(color: .black.opacity(0.22), location: 0),
                .init(color: .white.opacity(0.16), location: 0.45),
                .init(color: .black.opacity(0.10), location: 0.75),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
            .frame(width: max(5, width * 0.055))
            .blendMode(.overlay)
        }
        .overlay {
            RoundedRectangle(cornerRadius: max(2, width * 0.018), style: .continuous)
                .strokeBorder(.black.opacity(0.10), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.10), radius: 1, x: 0, y: 1)
        .shadow(color: .black.opacity(0.18), radius: width * 0.07, x: 0, y: width * 0.05)
        .task(id: "\(entry.book.coverFile ?? "")#\(version)") {
            guard let url = entry.coverURL else { image = nil; return }
            image = await CoverCache.shared.image(for: url, version: version, maxPixel: Int(width * 3))
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

struct StarRating: View {
    var rating: Int?
    var size: CGFloat = 12
    var onChange: ((Int?) -> Void)?
    @Environment(\.palette) private var palette
    @State private var hover: Int?

    var body: some View {
        HStack(spacing: size * 0.18) {
            ForEach(1...5, id: \.self) { star in
                let filled = star <= (hover ?? rating ?? 0)
                Image(systemName: filled ? "star.fill" : "star")
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(filled ? Color(hex: 0xD99A2B) : palette.tertiary.opacity(0.7))
                    .contentShape(Rectangle())
                    .onHover { inside in
                        guard onChange != nil else { return }
                        hover = inside ? star : (hover == star ? nil : hover)
                    }
                    .onTapGesture {
                        // Clicking the current rating clears it.
                        onChange?(rating == star ? nil : star)
                    }
            }
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
