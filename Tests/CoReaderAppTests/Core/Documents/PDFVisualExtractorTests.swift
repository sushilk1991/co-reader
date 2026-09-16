import AppKit
import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import CoReaderApp

struct PDFVisualExtractorTests {
    @Test
    func extractorReturnsEmbeddedImageAssetsForPDFWithImages() throws {
        let fixtureURL = try makePDFWithEmbeddedImage()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let visuals = try PDFVisualExtractor().extract(from: fixtureURL)

        #expect(visuals.count == 1)
        #expect(visuals[0].pageIndex == 0)
        #expect(visuals[0].kind == .embeddedImage)
        #expect(!visuals[0].imageData.isEmpty)
        #expect(visuals[0].suggestedFilename.contains("page-1"))
        #expect(visuals[0].pixelWidth < 400)
        #expect(visuals[0].pixelHeight < 300)
    }

    @Test
    func extractorSkipsTextOnlyPDFs() throws {
        let fixtureURL = try makeTextOnlyPDF()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let visuals = try PDFVisualExtractor().extract(from: fixtureURL)

        #expect(visuals.isEmpty)
    }

    @Test
    func pageSnapshotPreservesTopAndBottomOrientation() throws {
        let fixtureURL = try makePDFWithOrientationBands()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let snapshot = try PDFVisualExtractor().renderPageSnapshot(from: fixtureURL, pageIndex: 0)
        let visual = try #require(snapshot)
        let bitmap = try #require(NSBitmapImageRep(data: visual.imageData))

        // Bitmap rows count from the top: the red band (page y 220..290 of 320) is the top 18 %.
        let sampleX = bitmap.pixelsWide / 2
        let topSampleY = Int(Double(bitmap.pixelsHigh) * 0.18)
        let bottomSampleY = Int(Double(bitmap.pixelsHigh) * 0.82)
        let topColor = try #require(bitmap.colorAt(x: sampleX, y: topSampleY))
        let bottomColor = try #require(bitmap.colorAt(x: sampleX, y: bottomSampleY))

        #expect(topColor.redComponent > topColor.blueComponent)
        #expect(bottomColor.blueComponent > bottomColor.redComponent)
    }

    /// The extractor's own render must agree with PDFKit's upright drawing of the same page:
    /// the red figure occupies the same pixel rows in both.
    @Test
    func pageSnapshotMatchesPDFKitReference() throws {
        let fixtureURL = try makeNestedFormFigurePDF()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let snapshot = try #require(try PDFVisualExtractor().renderPageSnapshot(from: fixtureURL, pageIndex: 0))
        let snapshotBitmap = try #require(NSBitmapImageRep(data: snapshot.imageData))
        let rendered = try redPixels(in: snapshotBitmap)
        let reference = try redPixels(in: pdfKitReference(for: fixtureURL, pixelWidth: snapshot.pixelWidth, pixelHeight: snapshot.pixelHeight))

        let renderedBounds = try #require(rendered.bounds)
        let referenceBounds = try #require(reference.bounds)
        #expect(abs(renderedBounds.minY - referenceBounds.minY) <= 1)
        #expect(abs(renderedBounds.maxY - referenceBounds.maxY) <= 1)
        #expect(abs(renderedBounds.minX - referenceBounds.minX) <= 1)
        #expect(abs(renderedBounds.maxX - referenceBounds.maxX) <= 1)
    }

    /// A figure drawn through nested forms in the upper third of the page: the scanner's
    /// placement must match where CoreGraphics draws it, and the crop must contain the
    /// figure. A vertically mirrored crop lands on white paper and fails the red threshold.
    @Test
    func nestedFormFigureCropContainsTheFigure() throws {
        let fixtureURL = try makeNestedFormFigurePDF()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }
        let page = try #require(PDFDocument(url: fixtureURL)?.page(at: 0))

        let placements = PDFImagePlacementScanner().imagePlacements(for: page)
        let snapshot = try #require(try PDFVisualExtractor().renderPageSnapshot(from: fixtureURL, pageIndex: 0))
        let snapshotBitmap = try #require(NSBitmapImageRep(data: snapshot.imageData))
        let renderedFigure = try #require(redPixels(in: snapshotBitmap).bounds)
        let visuals = try PDFVisualExtractor().extract(from: fixtureURL)

        // Scanner placement is in page points (y up); the render is 2 px per point with rows from the top.
        #expect(placements == [nestedFormFigureRect])
        let scale = CGFloat(snapshot.pixelHeight) / nestedFormPageSize.height
        let expectedRows = (nestedFormPageSize.height - nestedFormFigureRect.maxY) * scale ... (nestedFormPageSize.height - nestedFormFigureRect.minY) * scale
        #expect(abs(renderedFigure.minY - expectedRows.lowerBound) <= 1)
        #expect(abs(renderedFigure.maxY - expectedRows.upperBound) <= 1)
        #expect(abs(renderedFigure.minX - nestedFormFigureRect.minX * scale) <= 1)

        #expect(visuals.count == 1)
        let visual = try #require(visuals.first)
        let cropBitmap = try #require(NSBitmapImageRep(data: visual.imageData))
        let crop = try redPixels(in: cropBitmap)
        #expect(crop.fraction >= minimumFigureCoverage, "crop is \(crop.fraction) red")
    }
}

// MARK: Nested-form fixture

/// Page points, origin bottom-left: the figure sits in the upper third so a mirrored crop cannot pass by luck.
private let nestedFormPageSize = CGSize(width: 300, height: 300)
private let nestedFormFigureRect = CGRect(x: 150, y: 180, width: 100, height: 100)

/// The crop is inset 4 px on each side, so a correct 200 px figure fills ~92 % of a 208 px crop;
/// the mirrored crop measured 1 %.
private let minimumFigureCoverage = 0.85

/// Hand-built one-page PDF. `Im1` (2x2 red) is drawn through two nested forms:
/// `page: translate (150,180) -> Fm1: scale 0.5 -> Fm2: image 200x200`, giving
/// the 100x100 figure at `nestedFormFigureRect`.
private func makeNestedFormFigurePDF() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-nested-form.pdf")
    let redPixels = Data([0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00, 0xFF, 0x00, 0x00])

    func stream(_ dictionary: String, _ content: Data) -> Data {
        var data = Data("<< \(dictionary) /Length \(content.count) >>\nstream\n".utf8)
        data.append(content)
        data.append(Data("\nendstream".utf8))
        return data
    }

    let objects: [Data] = [
        Data("<< /Type /Catalog /Pages 2 0 R >>".utf8),
        Data("<< /Type /Pages /Kids [3 0 R] /Count 1 >>".utf8),
        Data("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 300] /Contents 4 0 R /Resources << /XObject << /Fm1 6 0 R >> >> >>".utf8),
        stream("", Data("q 1 0 0 1 150 180 cm /Fm1 Do Q".utf8)),
        stream("/Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceRGB /BitsPerComponent 8", redPixels),
        stream("/Type /XObject /Subtype /Form /BBox [0 0 300 300] /Matrix [0.5 0 0 0.5 0 0] /Resources << /XObject << /Fm2 7 0 R >> >>", Data("q /Fm2 Do Q".utf8)),
        stream("/Type /XObject /Subtype /Form /BBox [0 0 300 300] /Matrix [1 0 0 1 0 0] /Resources << /XObject << /Im1 5 0 R >> >>", Data("q 200 0 0 200 0 0 cm /Im1 Do Q".utf8))
    ]

    var body = Data("%PDF-1.4\n".utf8)
    var offsets: [Int] = []
    for (index, object) in objects.enumerated() {
        offsets.append(body.count)
        body.append(Data("\(index + 1) 0 obj\n".utf8))
        body.append(object)
        body.append(Data("\nendobj\n".utf8))
    }
    let xrefOffset = body.count
    var trailer = "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    for offset in offsets {
        trailer += String(format: "%010d 00000 n \n", offset)
    }
    trailer += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
    body.append(Data(trailer.utf8))

    try body.write(to: url)
    return url
}

/// PDFKit's own upright drawing of the page into a bottom-left-origin bitmap; independent of the extractor.
private func pdfKitReference(for url: URL, pixelWidth: Int, pixelHeight: Int) throws -> NSBitmapImageRep {
    let page = try #require(PDFDocument(url: url)?.page(at: 0))
    let context = try #require(CGContext(
        data: nil,
        width: pixelWidth,
        height: pixelHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(NSColor.white.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
    context.scaleBy(
        x: CGFloat(pixelWidth) / page.bounds(for: .mediaBox).width,
        y: CGFloat(pixelHeight) / page.bounds(for: .mediaBox).height
    )
    page.draw(with: .mediaBox, to: context)
    let image = try #require(context.makeImage())
    return NSBitmapImageRep(cgImage: image)
}

private struct RedPixelSummary {
    let count: Int
    let total: Int
    /// Pixel bounds with rows counted from the top, matching `CGImage.cropping`.
    let bounds: CGRect?

    var fraction: Double { Double(count) / Double(max(total, 1)) }
}

/// Counts saturated red pixels (`r > 200, g < 80, b < 80`) and their bounding box.
private func redPixels(in bitmap: NSBitmapImageRep) throws -> RedPixelSummary {
    try #require(bitmap.bitsPerSample == 8 && !bitmap.isPlanar)
    let data = try #require(bitmap.bitmapData)
    let stride = bitmap.bitsPerPixel / 8
    var count = 0
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1

    for y in 0 ..< bitmap.pixelsHigh {
        for x in 0 ..< bitmap.pixelsWide {
            let offset = y * bitmap.bytesPerRow + x * stride
            guard data[offset] > 200, data[offset + 1] < 80, data[offset + 2] < 80 else {
                continue
            }
            count += 1
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }

    let bounds = count == 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    return RedPixelSummary(count: count, total: bitmap.pixelsWide * bitmap.pixelsHigh, bounds: bounds)
}

private func makePDFWithEmbeddedImage() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
    let pageRect = CGRect(x: 0, y: 0, width: 320, height: 320)
    var mediaBox = pageRect
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw TestFixtureError.unableToCreatePDF
    }

    context.beginPDFPage([kCGPDFContextMediaBox as String: pageRect] as CFDictionary)
    let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext

    NSColor.white.setFill()
    NSBezierPath(rect: pageRect).fill()

    let image = NSImage(size: NSSize(width: 120, height: 80))
    image.lockFocus()
    NSColor.systemTeal.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 120, height: 80)).fill()
    NSColor.white.setStroke()
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 12, y: 20))
    path.line(to: NSPoint(x: 58, y: 62))
    path.line(to: NSPoint(x: 108, y: 18))
    path.lineWidth = 6
    path.stroke()
    image.unlockFocus()

    image.draw(in: NSRect(x: 96, y: 120, width: 128, height: 96))

    let title = NSString(string: "Figure 1. Multi-agent workflow")
    title.draw(
        at: NSPoint(x: 72, y: 86),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
    )

    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    return url
}

private func makeTextOnlyPDF() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-text.pdf")
    let pageRect = CGRect(x: 0, y: 0, width: 320, height: 320)
    var mediaBox = pageRect
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw TestFixtureError.unableToCreatePDF
    }

    context.beginPDFPage([kCGPDFContextMediaBox as String: pageRect] as CFDictionary)
    let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext

    NSColor.white.setFill()
    NSBezierPath(rect: pageRect).fill()

    let text = NSString(string: "Only text lives on this page. There should be no extracted visual asset.")
    text.draw(
        in: NSRect(x: 40, y: 120, width: 240, height: 100),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: 18),
            .foregroundColor: NSColor.labelColor
        ]
    )

    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    return url
}

private func makePDFWithOrientationBands() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString)-orientation.pdf")
    let pageRect = CGRect(x: 0, y: 0, width: 280, height: 320)
    var mediaBox = pageRect
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        throw TestFixtureError.unableToCreatePDF
    }

    context.beginPDFPage([kCGPDFContextMediaBox as String: pageRect] as CFDictionary)
    let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext

    NSColor.white.setFill()
    NSBezierPath(rect: pageRect).fill()

    NSColor.systemRed.setFill()
    NSBezierPath(rect: NSRect(x: 40, y: 220, width: 200, height: 70)).fill()

    NSColor.systemBlue.setFill()
    NSBezierPath(rect: NSRect(x: 40, y: 30, width: 200, height: 70)).fill()

    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    return url
}

private enum TestFixtureError: Error {
    case unableToCreatePDF
}
