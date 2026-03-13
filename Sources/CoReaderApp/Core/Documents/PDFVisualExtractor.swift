import AppKit
import CoreGraphics
import Foundation
import PDFKit

struct PDFVisualExtractor {
    func extract(from url: URL) throws -> [DocumentVisualAsset] {
        guard let document = PDFDocument(url: url) else {
            throw PDFVisualExtractorError.unableToOpenDocument
        }

        return try (0 ..< document.pageCount).compactMap { pageIndex in
            guard let page = document.page(at: pageIndex), pageContainsImage(page) else {
                return nil
            }

            return try makeSnapshotAsset(
                page: page,
                pageIndex: pageIndex,
                baseName: url.deletingPathExtension().lastPathComponent
            )
        }
    }

    func renderPageSnapshot(from url: URL, pageIndex: Int) throws -> DocumentVisualAsset? {
        guard let document = PDFDocument(url: url) else {
            throw PDFVisualExtractorError.unableToOpenDocument
        }

        guard let page = document.page(at: pageIndex) else {
            return nil
        }

        return try makeSnapshotAsset(
            page: page,
            pageIndex: pageIndex,
            baseName: url.deletingPathExtension().lastPathComponent
        )
    }

    private func pageContainsImage(_ page: PDFPage) -> Bool {
        guard let pageRef = page.pageRef,
              let pageDictionary = pageRef.dictionary else {
            return false
        }

        return dictionaryContainsImage(pageDictionary)
    }

    private func dictionaryContainsImage(_ dictionary: CGPDFDictionaryRef) -> Bool {
        var resources: CGPDFDictionaryRef?
        if CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources,
           xObjectDictionaryContainsImage(in: resources) {
            return true
        }

        return xObjectDictionaryContainsImage(in: dictionary)
    }

    private func xObjectDictionaryContainsImage(in dictionary: CGPDFDictionaryRef) -> Bool {
        var xObjectDictionary: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "XObject", &xObjectDictionary),
              let xObjectDictionary else {
            return false
        }

        let state = PDFImageSearchState()
        CGPDFDictionaryApplyBlock(
            xObjectDictionary,
            { _, object, info in
                guard let info else {
                    return true
                }

                let state = Unmanaged<PDFImageSearchState>.fromOpaque(info).takeUnretainedValue()
                if self.objectContainsImage(object) {
                    state.didFindImage = true
                    return false
                }

                return true
            },
            Unmanaged.passUnretained(state).toOpaque()
        )
        return state.didFindImage
    }

    private func objectContainsImage(_ object: CGPDFObjectRef) -> Bool {
        guard CGPDFObjectGetType(object) == .stream else {
            return false
        }

        var stream: CGPDFStreamRef?
        guard CGPDFObjectGetValue(object, .stream, &stream), let stream,
              let dictionary = CGPDFStreamGetDictionary(stream) else {
            return false
        }

        var subtypeName: UnsafePointer<CChar>?
        guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtypeName),
              let subtypeName else {
            return false
        }

        switch String(cString: subtypeName) {
        case "Image":
            return true
        case "Form":
            return dictionaryContainsImage(dictionary)
        default:
            return false
        }
    }

    private func makeSnapshotAsset(
        page: PDFPage,
        pageIndex: Int,
        baseName: String
    ) throws -> DocumentVisualAsset {
        let pageBounds = page.bounds(for: .mediaBox)
        let maxDimension: CGFloat = 1_600
        let scale = maxDimension / max(pageBounds.width, pageBounds.height)
        let renderScale = max(1, min(scale, 2))
        let pixelWidth = max(Int(pageBounds.width * renderScale), 1)
        let pixelHeight = max(Int(pageBounds.height * renderScale), 1)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw PDFVisualExtractorError.unableToRenderSnapshot
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = graphicsContext

        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)).fill()

        let context = graphicsContext.cgContext
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: renderScale, y: -renderScale)
        page.draw(with: .mediaBox, to: context)
        context.restoreGState()

        guard let imageData = bitmap.representation(using: .png, properties: [:]) else {
            throw PDFVisualExtractorError.unableToEncodeSnapshot
        }

        return DocumentVisualAsset(
            id: UUID(),
            pageIndex: pageIndex,
            kind: .pageSnapshot,
            imageData: imageData,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            suggestedFilename: suggestedFilename(baseName: baseName, pageIndex: pageIndex)
        )
    }

    private func suggestedFilename(baseName: String, pageIndex: Int) -> String {
        let sanitized = baseName
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return "\(sanitized)-page-\(pageIndex + 1)-visual.png"
    }
}

private final class PDFImageSearchState {
    var didFindImage = false
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
