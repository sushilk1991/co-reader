import AppKit
import PDFKit

final class HighlightingPDFView: PDFView {
    var isHighlightToolEnabled = false
    var selectedHighlightColor: ReaderHighlightColor = .yellow
    var onHighlightCapture: (([PDFDocumentHighlightDraft]) -> Void)?
    var onHighlightRemoval: ((UUID) -> Void)?

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
        guard let annotation = page.annotation(at: pagePoint),
              let userName = annotation.userName,
              userName.hasPrefix(Self.highlightUserNamePrefix) else {
            return nil
        }

        return UUID(uuidString: String(userName.dropFirst(Self.highlightUserNamePrefix.count)))
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

    func syncManagedHighlights(_ highlights: [PDFDocumentHighlight]) {
        guard let document else {
            return
        }

        for pageIndex in 0 ..< document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                continue
            }

            let managedAnnotations = page.annotations.filter {
                ($0.userName ?? "").hasPrefix(Self.highlightUserNamePrefix)
            }
            managedAnnotations.forEach(page.removeAnnotation)
        }

        for highlight in highlights {
            guard let page = document.page(at: highlight.pageIndex) else {
                continue
            }

            for rect in highlight.rects {
                let annotation = PDFAnnotation(bounds: rect.cgRect, forType: .highlight, withProperties: nil)
                annotation.color = highlight.color.annotationColor
                annotation.userName = Self.highlightUserNamePrefix + highlight.id.uuidString
                annotation.contents = highlight.quotedText
                annotation.shouldDisplay = true
                annotation.shouldPrint = false
                annotation.quadrilateralPoints = rect.quadrilateralPoints.map(NSValue.init(point:))
                page.addAnnotation(annotation)
            }
        }
    }

    private static let highlightUserNamePrefix = "coreader-highlight:"
}
