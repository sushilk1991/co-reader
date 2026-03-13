import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import CoReaderApp

struct PDFVisualExtractorTests {
    @Test
    func extractorReturnsPageScopedVisualAssetsForPDFWithImages() throws {
        let fixtureURL = try makePDFWithEmbeddedImage()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let visuals = try PDFVisualExtractor().extract(from: fixtureURL)

        #expect(visuals.count == 1)
        #expect(visuals[0].pageIndex == 0)
        #expect(visuals[0].kind == .embeddedImage || visuals[0].kind == .pageSnapshot)
        #expect(!visuals[0].imageData.isEmpty)
        #expect(visuals[0].suggestedFilename.contains("page-1"))
    }

    @Test
    func extractorSkipsTextOnlyPDFs() throws {
        let fixtureURL = try makeTextOnlyPDF()
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let visuals = try PDFVisualExtractor().extract(from: fixtureURL)

        #expect(visuals.isEmpty)
    }
}

private func makePDFWithEmbeddedImage() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pdf")
    let pageRect = CGRect(x: 0, y: 0, width: 320, height: 320)
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
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
    guard let consumer = CGDataConsumer(url: url as CFURL),
          let context = CGContext(consumer: consumer, mediaBox: nil, nil) else {
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

private enum TestFixtureError: Error {
    case unableToCreatePDF
}
