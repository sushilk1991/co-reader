import CoreGraphics
import Foundation
import PDFKit

struct PDFImagePlacementScanner {
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
            currentTransform: .identity
        )
        return collector.deduplicatedPlacements()
    }
}

private func scanPDFContentStream(
    _ contentStream: CGPDFContentStreamRef,
    collector: PDFImagePlacementCollector,
    currentTransform: CGAffineTransform
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
        currentTransform: currentTransform
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
            currentTransform: state.currentTransform.concatenating(formMatrix(in: dictionary))
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
    var currentTransform: CGAffineTransform
    var graphicsStateStack: [CGAffineTransform] = []

    init(collector: PDFImagePlacementCollector, currentTransform: CGAffineTransform) {
        self.collector = collector
        self.currentTransform = currentTransform
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
