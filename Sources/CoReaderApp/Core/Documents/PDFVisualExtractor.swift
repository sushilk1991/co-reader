import AppKit
import CoreGraphics
import Foundation
import PDFKit

struct PDFVisualExtractor {
    private let placementScanner = PDFImagePlacementScanner()

    func extract(
        from url: URL,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        onProgress: @escaping @Sendable (PageScanProgress) -> Void = { _ in }
    ) throws -> [DocumentVisualAsset] {
        guard let document = PDFDocument(url: url) else {
            throw PDFVisualExtractorError.unableToOpenDocument
        }

        var visuals: [DocumentVisualAsset] = []
        let baseName = url.deletingPathExtension().lastPathComponent

        for pageIndex in 0 ..< document.pageCount {
            // Every page is scanned and possibly rendered, so this is the natural
            // place to stop early and to report how far the scan has come.
            guard !isCancelled() else {
                throw CancellationError()
            }
            defer { onProgress(PageScanProgress(completedPages: pageIndex + 1, totalPages: document.pageCount)) }

            guard let page = document.page(at: pageIndex) else {
                continue
            }

            let placements = placementScanner.imagePlacements(for: page)
            guard !placements.isEmpty else {
                continue
            }

            let renderedPage = try renderPage(page)
            for (imageIndex, placement) in placements.enumerated() {
                if let visual = try makeEmbeddedImageAsset(
                    from: renderedPage,
                    placement: placement,
                    pageIndex: pageIndex,
                    imageIndex: imageIndex,
                    baseName: baseName
                ) {
                    visuals.append(visual)
                }
            }
        }

        return visuals
    }

    func renderPageSnapshot(from url: URL, pageIndex: Int) throws -> DocumentVisualAsset? {
        guard let document = PDFDocument(url: url) else {
            throw PDFVisualExtractorError.unableToOpenDocument
        }

        guard let page = document.page(at: pageIndex) else {
            return nil
        }

        let renderedPage = try renderPage(page)
        let imageData = try pngData(from: renderedPage.image)
        let baseName = url.deletingPathExtension().lastPathComponent

        return DocumentVisualAsset(
            id: UUID(),
            pageIndex: pageIndex,
            kind: .pageSnapshot,
            imageData: imageData,
            pixelWidth: renderedPage.image.width,
            pixelHeight: renderedPage.image.height,
            suggestedFilename: snapshotFilename(baseName: baseName, pageIndex: pageIndex)
        )
    }

    private func renderPage(_ page: PDFPage) throws -> RenderedPDFPage {
        guard let pageRef = page.pageRef else {
            throw PDFVisualExtractorError.unableToRenderSnapshot
        }

        let pageBounds = page.bounds(for: .mediaBox)
        let renderRect = CGRect(origin: .zero, size: pageBounds.size)
        let maxDimension: CGFloat = 1_600
        let scale = maxDimension / max(pageBounds.width, pageBounds.height)
        let renderScale = max(1, min(scale, 2))
        let pixelWidth = max(Int((renderRect.width * renderScale).rounded(.up)), 1)
        let pixelHeight = max(Int((renderRect.height * renderScale).rounded(.up)), 1)

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PDFVisualExtractorError.unableToRenderSnapshot
        }

        let drawingTransform = pageRef.getDrawingTransform(
            .mediaBox,
            rect: renderRect,
            rotate: 0,
            preserveAspectRatio: true
        )
        // The bitmap context shares PDF user space's bottom-left origin, so drawing needs
        // only the scale. `CGImage.cropping` counts rows from the top, so the crop
        // transform adds the vertical flip on top of the drawing one.
        //
        //  page (pt, y up) --scale--> context (px, y up) --flip--> image rows (px, y down)
        let pageToContextTransform = drawingTransform.concatenating(
            CGAffineTransform(scaleX: renderScale, y: renderScale)
        )
        let pageToImageTransform = pageToContextTransform.concatenating(
            CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(pixelHeight))
        )

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.interpolationQuality = .high
        context.saveGState()
        context.concatenate(pageToContextTransform)
        context.drawPDFPage(pageRef)
        context.restoreGState()

        guard let image = context.makeImage() else {
            throw PDFVisualExtractorError.unableToRenderSnapshot
        }

        return RenderedPDFPage(
            image: image,
            pageToImageTransform: pageToImageTransform
        )
    }

    private func makeEmbeddedImageAsset(
        from renderedPage: RenderedPDFPage,
        placement: CGRect,
        pageIndex: Int,
        imageIndex: Int,
        baseName: String
    ) throws -> DocumentVisualAsset? {
        let cropRect = renderedPage.pixelCropRect(for: placement)
        guard cropRect.width >= 48,
              cropRect.height >= 48,
              let croppedImage = renderedPage.image.cropping(to: cropRect) else {
            return nil
        }

        return DocumentVisualAsset(
            id: UUID(),
            pageIndex: pageIndex,
            kind: .embeddedImage,
            imageData: try pngData(from: croppedImage),
            pixelWidth: croppedImage.width,
            pixelHeight: croppedImage.height,
            suggestedFilename: embeddedImageFilename(
                baseName: baseName,
                pageIndex: pageIndex,
                imageIndex: imageIndex
            )
        )
    }

    private func pngData(from image: CGImage) throws -> Data {
        let representation = NSBitmapImageRep(cgImage: image)
        guard let imageData = representation.representation(using: .png, properties: [:]) else {
            throw PDFVisualExtractorError.unableToEncodeSnapshot
        }

        return imageData
    }

    private func snapshotFilename(baseName: String, pageIndex: Int) -> String {
        "\(sanitizedBaseName(baseName))-page-\(pageIndex + 1)-snapshot.png"
    }

    private func embeddedImageFilename(baseName: String, pageIndex: Int, imageIndex: Int) -> String {
        "\(sanitizedBaseName(baseName))-page-\(pageIndex + 1)-figure-\(imageIndex + 1).png"
    }

    private func sanitizedBaseName(_ baseName: String) -> String {
        baseName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}

private struct RenderedPDFPage {
    let image: CGImage
    let pageToImageTransform: CGAffineTransform

    func pixelCropRect(for pageRect: CGRect) -> CGRect {
        let transformedRect = pageRect
            .applying(pageToImageTransform)
            .standardized
            .insetBy(dx: -4, dy: -4)
            .integral

        let imageBounds = CGRect(
            x: 0,
            y: 0,
            width: image.width,
            height: image.height
        )

        return transformedRect.intersection(imageBounds)
    }
}

enum PDFVisualExtractorError: LocalizedError {
    case unableToOpenDocument
    case unableToRenderSnapshot
    case unableToEncodeSnapshot

    var errorDescription: String? {
        switch self {
        case .unableToOpenDocument:
            return "Unable to open PDF document for visual extraction."
        case .unableToRenderSnapshot:
            return "Unable to render a PDF page snapshot."
        case .unableToEncodeSnapshot:
            return "Unable to encode the extracted PDF visual."
        }
    }
}
