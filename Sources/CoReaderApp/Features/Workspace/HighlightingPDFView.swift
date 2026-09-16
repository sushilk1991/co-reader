import AppKit
import PDFKit

final class HighlightingPDFView: PDFView {
    var isHighlightToolEnabled = false
    var selectedHighlightColor: ReaderHighlightColor = .yellow
    var onHighlightCapture: (([PDFDocumentHighlightDraft]) -> Void)?
    var onHighlightRemoval: ((UUID) -> Void)?
    /// Fires after each layout pass; the coordinator uses it to re-apply a restored page.
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        captureSelectionAsHighlightIfNeeded()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        if let highlightID = managedHighlightID(at: event) {
            let menu = NSMenu()
            let removeItem = NSMenuItem(title: "Remove Highlight", action: #selector(removeHighlightFromMenu(_:)), keyEquivalent: "")
            removeItem.representedObject = highlightID
            removeItem.target = self
            menu.addItem(removeItem)
            return menu
        }

        return super.menu(for: event)
    }

    @objc
    private func removeHighlightFromMenu(_ sender: NSMenuItem) {
        guard let highlightID = sender.representedObject as? UUID else {
            return
        }

        onHighlightRemoval?(highlightID)
    }

    private func captureSelectionAsHighlightIfNeeded() {
        guard isHighlightToolEnabled,
              let document,
              let currentSelection,
              let selectedString = normalizedText(from: currentSelection.string) else {
            return
        }

        let lineSelections = currentSelection.selectionsByLine()
        var drafts: [PDFDocumentHighlightDraft] = []

        for page in currentSelection.pages {
            let pageSelections = lineSelections
                .filter { $0.pages.first == page }
                .compactMap { selection -> (CGRect, String)? in
                    let bounds = selection.bounds(for: page).standardized
                    guard !bounds.isNull,
                          bounds.width > 0,
                          bounds.height > 0,
                          let text = normalizedText(from: selection.string) else {
                        return nil
                    }
                    return (bounds, text)
                }

            guard !pageSelections.isEmpty else {
                continue
            }

            let pageIndex = document.index(for: page)
            let quotedText = pageSelections.map(\.1).joined(separator: " ")

            drafts.append(
                PDFDocumentHighlightDraft(
                    id: UUID(),
                    pageIndex: pageIndex,
                    quotedText: quotedText.isEmpty ? selectedString : quotedText,
                    color: selectedHighlightColor,
                    rects: pageSelections.map(\.0)
                )
            )
        }

        guard !drafts.isEmpty else {
            return
        }

        onHighlightCapture?(drafts)
        super.clearSelection()
    }

    private func managedHighlightID(at event: NSEvent) -> UUID? {
        let localPoint = convert(event.locationInWindow, from: nil)
        guard let page = page(for: localPoint, nearest: true) else {
            return nil
        }

        let pagePoint = convert(localPoint, to: page)
        guard let annotation = page.annotation(at: pagePoint) else {
            return nil
        }

        return managedHighlightID(of: annotation)
    }

    private func normalizedText(from value: String?) -> String? {
        let text = value?
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else {
            return nil
        }

        return text
    }

    /// Brings the page annotations in line with `highlights` by diffing, so an
    /// unchanged highlight keeps its `PDFAnnotation` instance. Removing and
    /// re-adding every annotation on each SwiftUI update made PDFKit re-layout and
    /// flicker while scrolling.
    ///
    /// ```
    ///  installed (by id) ─┬─ id not desired, or rects/colour differ ──▶ remove
    ///                     └─ matches desired ───────────────────────▶ keep
    ///  desired (by id) ───── not installed after the pass ──────────▶ add
    /// ```
    func syncManagedHighlights(_ highlights: [PDFDocumentHighlight]) {
        guard let document else {
            return
        }

        let desired = Dictionary(highlights.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var installedIDs: Set<UUID> = []

        for (id, annotations) in managedAnnotationsByID(in: document) {
            guard let highlight = desired[id], annotationsMatch(annotations, highlight: highlight) else {
                for (page, annotation) in annotations {
                    page.removeAnnotation(annotation)
                }
                continue
            }

            installedIDs.insert(id)
        }

        for highlight in highlights where !installedIDs.contains(highlight.id) {
            guard let page = document.page(at: highlight.pageIndex) else {
                continue
            }

            for rect in highlight.rects {
                page.addAnnotation(makeAnnotation(for: highlight, rect: rect))
            }
            installedIDs.insert(highlight.id)
        }
    }

    private func managedAnnotationsByID(in document: PDFDocument) -> [UUID: [(page: PDFPage, annotation: PDFAnnotation)]] {
        var byID: [UUID: [(page: PDFPage, annotation: PDFAnnotation)]] = [:]

        for pageIndex in 0 ..< document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                continue
            }

            for annotation in page.annotations {
                guard let id = managedHighlightID(of: annotation) else {
                    continue
                }

                byID[id, default: []].append((page, annotation))
            }
        }

        return byID
    }

    private func annotationsMatch(_ annotations: [(page: PDFPage, annotation: PDFAnnotation)], highlight: PDFDocumentHighlight) -> Bool {
        guard let document, annotations.count == highlight.rects.count else {
            return false
        }

        let expectedColor = highlight.color.annotationColor
        let installedBounds = annotations.map(\.annotation.bounds)

        return annotations.allSatisfy { entry in
            document.index(for: entry.page) == highlight.pageIndex &&
                entry.annotation.color == expectedColor &&
                entry.annotation.contents == highlight.quotedText
        } && highlight.rects.allSatisfy { rect in
            installedBounds.contains { $0.equalTo(rect.cgRect) }
        }
    }

    private func makeAnnotation(for highlight: PDFDocumentHighlight, rect: PDFDocumentHighlight.HighlightRect) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: rect.cgRect, forType: .highlight, withProperties: nil)
        annotation.color = highlight.color.annotationColor
        annotation.userName = Self.highlightUserNamePrefix + highlight.id.uuidString
        annotation.contents = highlight.quotedText
        annotation.shouldDisplay = true
        annotation.shouldPrint = false
        annotation.quadrilateralPoints = rect.quadrilateralPoints.map(NSValue.init(point:))
        return annotation
    }

    private func managedHighlightID(of annotation: PDFAnnotation) -> UUID? {
        guard let userName = annotation.userName,
              userName.hasPrefix(Self.highlightUserNamePrefix) else {
            return nil
        }

        return UUID(uuidString: String(userName.dropFirst(Self.highlightUserNamePrefix.count)))
    }

    private static let highlightUserNamePrefix = "coreader-highlight:"
}
