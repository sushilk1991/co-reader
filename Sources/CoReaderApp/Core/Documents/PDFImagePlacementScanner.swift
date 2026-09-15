import CoreGraphics
import Foundation
import PDFKit

struct PDFImagePlacementScanner {
    /// Real documents nest forms a handful of levels deep; anything beyond this is
    /// either malformed or hostile, and each level costs native stack.
    static let defaultMaxFormDepth = 12

    private let maxFormDepth: Int

    init(maxFormDepth: Int = PDFImagePlacementScanner.defaultMaxFormDepth) {
        self.maxFormDepth = maxFormDepth
    }

    func imagePlacements(for page: PDFPage) -> [CGRect] {
        guard let pageRef = page.pageRef else {
            return []
        }

        let contentStream = CGPDFContentStreamCreateWithPage(pageRef)
        defer { CGPDFContentStreamRelease(contentStream) }

        let collector = PDFImagePlacementCollector(pageBounds: page.bounds(for: .mediaBox))
        scanPDFContentStream(
            contentStream,
            collector: collector,
            currentTransform: .identity,
            nesting: PDFFormNesting(limit: maxFormDepth)
        )
        return collector.deduplicatedPlacements()
    }
}

/// Tracks how deep the scanner is inside Form XObjects and which forms are on the
/// current path, so a form that draws itself (directly or via a cycle) is entered once.
///
/// ```
///  page ──Do Fm1──▶ Fm1 (depth 1) ──Do Fm2──▶ Fm2 (depth 2) ──Do Fm1──▶ skipped: ancestor
///                                              └──Do Fm3──▶ Fm3 (depth 3) … up to `limit`
/// ```
private struct PDFFormNesting {
    let depth: Int
    let ancestors: Set<CGPDFStreamRef>
    let limit: Int

    init(limit: Int) {
        self.init(depth: 0, ancestors: [], limit: limit)
    }

    private init(depth: Int, ancestors: Set<CGPDFStreamRef>, limit: Int) {
        self.depth = depth
        self.ancestors = ancestors
        self.limit = limit
    }

    func canEnter(form: CGPDFStreamRef) -> Bool {
        depth < limit && !ancestors.contains(form)
    }

    func entering(form: CGPDFStreamRef) -> PDFFormNesting {
        PDFFormNesting(depth: depth + 1, ancestors: ancestors.union([form]), limit: limit)
    }
}

private func scanPDFContentStream(
    _ contentStream: CGPDFContentStreamRef,
    collector: PDFImagePlacementCollector,
    currentTransform: CGAffineTransform,
    nesting: PDFFormNesting
) {
    guard let operatorTable = CGPDFOperatorTableCreate() else {
        return
    }
    defer { CGPDFOperatorTableRelease(operatorTable) }

    CGPDFOperatorTableSetCallback(operatorTable, "q", pushGraphicsStateCallback)
    CGPDFOperatorTableSetCallback(operatorTable, "Q", popGraphicsStateCallback)
    CGPDFOperatorTableSetCallback(operatorTable, "cm", concatenateMatrixCallback)
    CGPDFOperatorTableSetCallback(operatorTable, "Do", drawObjectCallback)

    let state = PDFImagePlacementScanState(
        collector: collector,
        currentTransform: currentTransform,
        nesting: nesting
    )
    let info = Unmanaged.passUnretained(state).toOpaque()
    let scanner = CGPDFScannerCreate(contentStream, operatorTable, info)
    defer { CGPDFScannerRelease(scanner) }
    _ = CGPDFScannerScan(scanner)
}

private func pushGraphicsStateCallback(scanner: CGPDFScannerRef, info: UnsafeMutableRawPointer?) {
    guard let info else {
        return
    }

    let state = Unmanaged<PDFImagePlacementScanState>.fromOpaque(info).takeUnretainedValue()
    state.graphicsStateStack.append(state.currentTransform)
}

private func popGraphicsStateCallback(scanner: CGPDFScannerRef, info: UnsafeMutableRawPointer?) {
    guard let info else {
        return
    }

    let state = Unmanaged<PDFImagePlacementScanState>.fromOpaque(info).takeUnretainedValue()
    state.currentTransform = state.graphicsStateStack.popLast() ?? .identity
}

private func concatenateMatrixCallback(scanner: CGPDFScannerRef, info: UnsafeMutableRawPointer?) {
    guard let info else {
        return
    }

    var f: CGPDFReal = 0
    var e: CGPDFReal = 0
    var d: CGPDFReal = 0
    var c: CGPDFReal = 0
    var b: CGPDFReal = 0
    var a: CGPDFReal = 0

    guard CGPDFScannerPopNumber(scanner, &f),
          CGPDFScannerPopNumber(scanner, &e),
          CGPDFScannerPopNumber(scanner, &d),
          CGPDFScannerPopNumber(scanner, &c),
          CGPDFScannerPopNumber(scanner, &b),
          CGPDFScannerPopNumber(scanner, &a) else {
        return
    }

    let state = Unmanaged<PDFImagePlacementScanState>.fromOpaque(info).takeUnretainedValue()
    let transform = CGAffineTransform(
        a: a,
        b: b,
        c: c,
        d: d,
        tx: e,
        ty: f
    )
    state.currentTransform = state.currentTransform.concatenating(transform)
}

private func drawObjectCallback(scanner: CGPDFScannerRef, info: UnsafeMutableRawPointer?) {
    guard let info else {
        return
    }

    var namePointer: UnsafePointer<CChar>?
    guard CGPDFScannerPopName(scanner, &namePointer),
          let namePointer else {
        return
    }

    let state = Unmanaged<PDFImagePlacementScanState>.fromOpaque(info).takeUnretainedValue()
    let contentStream = CGPDFScannerGetContentStream(scanner)
    guard let object = CGPDFContentStreamGetResource(contentStream, "XObject", namePointer) else {
        return
    }

    var stream: CGPDFStreamRef?
    guard CGPDFObjectGetValue(object, .stream, &stream),
          let stream,
          let dictionary = CGPDFStreamGetDictionary(stream),
          let subtype = pdfSubtypeName(in: dictionary) else {
        return
    }

    switch subtype {
    case "Image":
        state.collector.recordImagePlacement(
            CGRect(x: 0, y: 0, width: 1, height: 1).applying(state.currentTransform)
        )
    case "Form":
        guard state.nesting.canEnter(form: stream) else {
            return
        }
        var resources: CGPDFDictionaryRef?
        _ = CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources)
        guard let resources else {
            return
        }
        let nestedContentStream = CGPDFContentStreamCreateWithStream(
            stream,
            resources,
            contentStream
        )
        defer { CGPDFContentStreamRelease(nestedContentStream) }

        scanPDFContentStream(
            nestedContentStream,
            collector: state.collector,
            currentTransform: state.currentTransform.concatenating(formMatrix(in: dictionary)),
            nesting: state.nesting.entering(form: stream)
        )
    default:
        return
    }
}

private func pdfSubtypeName(in dictionary: CGPDFDictionaryRef) -> String? {
    var subtypeName: UnsafePointer<CChar>?
    guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtypeName),
          let subtypeName else {
        return nil
    }

    return String(cString: subtypeName)
}

private func formMatrix(in dictionary: CGPDFDictionaryRef) -> CGAffineTransform {
    var matrixArray: CGPDFArrayRef?
    guard CGPDFDictionaryGetArray(dictionary, "Matrix", &matrixArray),
          let matrixArray else {
        return .identity
    }

    var values = Array(repeating: CGFloat.zero, count: 6)
    for index in values.indices {
        var value: CGPDFReal = 0
        guard CGPDFArrayGetNumber(matrixArray, index, &value) else {
            return .identity
        }
        values[index] = value
    }

    return CGAffineTransform(
        a: values[0],
        b: values[1],
        c: values[2],
        d: values[3],
        tx: values[4],
        ty: values[5]
    )
}

private final class PDFImagePlacementScanState {
    let collector: PDFImagePlacementCollector
    let nesting: PDFFormNesting
    var currentTransform: CGAffineTransform
    var graphicsStateStack: [CGAffineTransform] = []

    init(collector: PDFImagePlacementCollector, currentTransform: CGAffineTransform, nesting: PDFFormNesting) {
        self.collector = collector
        self.currentTransform = currentTransform
        self.nesting = nesting
    }
}

private final class PDFImagePlacementCollector {
    private let pageBounds: CGRect
    private(set) var placements: [CGRect] = []

    init(pageBounds: CGRect) {
        self.pageBounds = pageBounds.standardized
    }

    func recordImagePlacement(_ placement: CGRect) {
        let clippedPlacement = placement.standardized.intersection(pageBounds)
        guard clippedPlacement.isFinite,
              !clippedPlacement.isNull,
              clippedPlacement.width >= 24,
              clippedPlacement.height >= 24 else {
            return
        }

        placements.append(clippedPlacement)
    }

    func deduplicatedPlacements() -> [CGRect] {
        var uniquePlacements: [CGRect] = []

        for placement in placements.sorted(by: placementSort) {
            guard !uniquePlacements.contains(where: { placementsMatch($0, placement) }) else {
                continue
            }

            uniquePlacements.append(placement)
        }

        return uniquePlacements
    }

    private func placementSort(lhs: CGRect, rhs: CGRect) -> Bool {
        if abs(lhs.maxY - rhs.maxY) > 1 {
            return lhs.maxY > rhs.maxY
        }

        return lhs.minX < rhs.minX
    }

    private func placementsMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let overlap = lhs.intersection(rhs)
        if !overlap.isNull {
            let minimumArea = max(min(lhs.area, rhs.area), 1)
            if overlap.area / minimumArea > 0.94 {
                return true
            }
        }

        return abs(lhs.minX - rhs.minX) < 1 &&
            abs(lhs.minY - rhs.minY) < 1 &&
            abs(lhs.width - rhs.width) < 1 &&
            abs(lhs.height - rhs.height) < 1
    }
}

private extension CGRect {
    var area: CGFloat {
        width * height
    }

    var isFinite: Bool {
        [origin.x, origin.y, width, height].allSatisfy(\.isFinite)
    }
}
