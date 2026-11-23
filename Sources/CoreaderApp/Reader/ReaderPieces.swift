import CoreaderKit
import SwiftUI

// MARK: - Selection bar

/// Appears over a selection: colours to highlight, then note, ask, explain, look up, copy.
struct SelectionBar: View {
    let reader: ReaderModel
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 2) {
            HStack(spacing: 7) {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    Button { reader.highlight(color) } label: {
                        Circle()
                            .fill(color.color)
                            .frame(width: 17, height: 17)
                            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                            .overlay {
                                if color == reader.lastColor {
                                    Circle().strokeBorder(palette.ink.opacity(0.55), lineWidth: 1.5).padding(-3)
                                }
                            }
                            .contentShape(Rectangle().inset(by: -4))
                    }
                    .buttonStyle(.plain)
                    .help("Highlight in \(color.rawValue)")
                    .accessibilityLabel("Highlight \(color.rawValue)")
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)

            divider
            action("Note", "square.and.pencil", help: "Highlight and add a note") { reader.noteOnSelection() }
            action("Ask", "sparkles", help: "Ask the AI about this passage") { reader.askAboutSelection() }
            action("Explain", "lightbulb", help: "A quick explanation, right here") { reader.glance(.explain) }
            divider
            icon("character.book.closed", help: "Look up") { reader.glance(.define) }
            icon("translate", help: "Translate") { reader.glance(.translate) }
            icon("doc.on.doc", help: "Copy") { reader.copySelection() }
                .padding(.trailing, 6)
        }
        .frame(height: 40)
        .background(palette.raised, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.rule, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
        .fixedSize()
    }

    private var divider: some View {
        Rectangle().fill(palette.rule).frame(width: 0.5, height: 18).padding(.horizontal, 3)
    }

    private func action(_ title: String, _ symbol: String, help: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 11.5, weight: .medium))
                Text(title).font(Typo.ui(12.5, weight: .medium))
            }
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverTint())
        .help(help)
    }

    private func icon(_ symbol: String, help: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(palette.secondary)
                .frame(width: 28, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverTint())
        .help(help)
        .accessibilityLabel(help)
    }
}

struct HoverTint: ButtonStyle {
    @Environment(\.palette) private var palette
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(palette.ink.opacity(configuration.isPressed ? 0.12 : (hovering ? 0.06 : 0)),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onHover { hovering = $0 }
    }
}

// MARK: - Quick explanation

struct GlanceCard: View {
    let reader: ReaderModel
    let glance: Glance
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(glance.kind.rawValue).labelStyle(palette)
                Spacer()
                Button { reader.glance = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.tertiary)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            if glance.isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Thinking…").font(Typo.ui(12.5)).foregroundStyle(palette.secondary)
                }
                .padding(.vertical, 6)
            } else {
                ScrollView {
                    Text(glance.answer)
                        .font(Typo.serif(14.5))
                        .lineSpacing(4)
                        .foregroundStyle(glance.failed ? palette.secondary : palette.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 220)
                if !glance.failed {
                    HStack(spacing: 14) {
                        Button("Keep as note") { reader.keepGlance() }
                        Button("Continue in chat") {
                            reader.selection = glance.selection
                            reader.glance = nil
                            reader.askAboutSelection()
                        }
                        Spacer()
                    }
                    .buttonStyle(.plain)
                    .font(Typo.ui(12, weight: .medium))
                    .foregroundStyle(palette.accent)
                }
            }
        }
        .padding(14)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.rule, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}

// MARK: - Highlight card

/// Opens when a highlight is clicked: change its colour, write its note, remove it.
struct AnnotationCard: View {
    let reader: ReaderModel
    let annotation: Annotation
    @Environment(\.palette) private var palette
    @State private var note = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    Button { reader.update(annotation.id, .color(color)) } label: {
                        Circle().fill(color.color).frame(width: 15, height: 15)
                            .overlay { if annotation.color == color { Circle().strokeBorder(palette.ink.opacity(0.55), lineWidth: 1.5).padding(-3) } }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Colour \(color.rawValue)")
                }
                Spacer()
                Button {
                    reader.selection = ReaderSelection(text: annotation.quote, context: annotation.quote, locator: annotation.locator,
                                                       chapter: annotation.chapter ?? "", rect: .zero)
                    reader.activeAnnotation = nil
                    reader.askAboutSelection()
                } label: { Image(systemName: "sparkles") }
                    .help("Ask the AI about this highlight")
                    .accessibilityLabel("Ask AI")
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(annotation.quote, forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .help("Copy")
                    .accessibilityLabel("Copy highlight")
                Button { reader.remove(annotation.id) } label: { Image(systemName: "trash") }
                    .help("Remove highlight")
                    .accessibilityLabel("Remove highlight")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(palette.secondary)

            ZStack(alignment: .topLeading) {
                if note.isEmpty {
                    Text("Add a note…")
                        .font(Typo.ui(13))
                        .foregroundStyle(palette.tertiary)
                        .padding(.top, 1)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $note)
                    .font(Typo.ui(13))
                    .foregroundStyle(palette.ink)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(minHeight: 64, maxHeight: 150)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.rule, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .onAppear {
            note = annotation.note
            focused = true
        }
        .onDisappear { commit() }
        .onChange(of: focused) { if !focused { commit() } }
    }

    private func commit() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != annotation.note, reader.annotations.contains(where: { $0.id == annotation.id }) else { return }
        reader.update(annotation.id, .note(trimmed))
    }
}

// MARK: - Snip

/// Drag out a rectangle of the page to save it as an image in the notes.
///
/// An AppKit view, not a SwiftUI gesture: it sits above the web or PDF view as a real
/// view, so the drag always reaches it instead of selecting text underneath.
struct SnipOverlay: NSViewRepresentable {
    let onSnip: (CGRect, Bool) -> Void
    let onCancel: () -> Void
    @Environment(\.palette) private var palette

    func makeNSView(context: Context) -> SnipView {
        let view = SnipView()
        view.onSnip = onSnip
        view.onCancel = onCancel
        view.accent = NSColor(palette.accent)
        view.setAccessibilityLabel("Snip area. Drag to select, Escape to cancel.")
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: SnipView, context: Context) {
        view.onSnip = onSnip
        view.onCancel = onCancel
    }
}

final class SnipView: NSView {
    var onSnip: (CGRect, Bool) -> Void = { _, _ in }
    var onCancel: () -> Void = {}
    var accent = NSColor.systemRed
    private var start: CGPoint?
    private var current: CGPoint?

    // Top-left origin, matching the reading area's coordinates.
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    // Snipping starts with the first press even if the window was not in front.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(current.x - start.x), height: abs(current.y - start.y))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        current = CGPoint(x: min(max(p.x, 0), bounds.width), y: min(max(p.y, 0), bounds.height))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let chosen = selection
        start = nil
        current = nil
        needsDisplay = true
        if let chosen, chosen.width > 12, chosen.height > 12 {
            onSnip(chosen, event.modifierFlags.contains(.option))
        } else {
            onCancel()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel() } else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim everything except the chosen area.
        let dim = NSBezierPath(rect: bounds)
        if let selection { dim.append(NSBezierPath(rect: selection)) }
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.28).setFill()
        dim.fill()

        if let selection {
            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
            accent.setStroke()
            border.setLineDash([5, 4], count: 2, phase: 0)
            border.stroke()
            drawLabel("\(Int(selection.width)) × \(Int(selection.height))", size: 10,
                      at: CGPoint(x: selection.minX, y: max(4, selection.minY - 22)), centered: false)
        } else {
            drawLabel("Drag over a figure, table or passage to save it to your notes.  Hold ⌥ to also copy it.  Esc to cancel.",
                      size: 12.5, at: CGPoint(x: bounds.midX, y: 18), centered: true)
        }
    }

    private func drawLabel(_ text: String, size: CGFloat, at point: CGPoint, centered: Bool) {
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor.white,
        ])
        let textSize = string.size()
        let padding = CGSize(width: size > 11 ? 14 : 6, height: size > 11 ? 8 : 2)
        var box = CGRect(x: point.x, y: point.y, width: textSize.width + padding.width * 2, height: textSize.height + padding.height * 2)
        if centered { box.origin.x -= box.width / 2 }
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: box.height / 2, yRadius: box.height / 2).fill()
        string.draw(at: CGPoint(x: box.minX + padding.width, y: box.minY + padding.height))
    }
}

// MARK: - Finished

struct FinishCard: View {
    let reader: ReaderModel
    @Environment(\.palette) private var palette
    @State private var rating: Int?

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Finished?").font(Typo.display(15)).foregroundStyle(palette.ink)
                Text("Rate it and move it to Read.").font(Typo.ui(12)).foregroundStyle(palette.secondary)
            }
            StarRating(rating: rating, size: 17) { rating = $0 }
            Button { reader.finish(rating: rating) } label: {
                Text("Mark as read")
                    .font(Typo.ui(12.5, weight: .semibold))
                    .foregroundStyle(palette.page)
                    .padding(.horizontal, 14).frame(height: 30)
                    .background(palette.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            Button { withAnimation { reader.showsFinishCard = false } } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.tertiary)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not yet")
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.rule, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}

// MARK: - Contents

struct ContentsPopover: View {
    let reader: ReaderModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Contents").labelStyle(palette).padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
            if reader.toc.isEmpty {
                Text("This document has no table of contents.")
                    .font(Typo.ui(12.5)).foregroundStyle(palette.secondary)
                    .padding(16)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(reader.toc) { item in
                                let current = item.label == reader.chapter
                                Button { reader.go(to: item) } label: {
                                    HStack(spacing: 8) {
                                        Text(item.label)
                                            .font(item.depth == 0 ? Typo.display(13.5, weight: current ? .semibold : .regular) : Typo.ui(12.5))
                                            .foregroundStyle(current ? palette.accent : (item.depth == 0 ? palette.ink : palette.secondary))
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.leading, 16 + CGFloat(item.depth) * 14)
                                    .padding(.trailing, 16)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(HoverTint())
                                .id(item.id)
                            }
                        }
                        .padding(.bottom, 10)
                    }
                    .onAppear {
                        if let current = reader.toc.first(where: { $0.label == reader.chapter }) { proxy.scrollTo(current.id, anchor: .center) }
                    }
                }
            }
        }
        .frame(width: 320)
        .frame(maxHeight: 520)
        .background(palette.raised)
    }
}

// MARK: - Search

struct SearchPopover: View {
    @Bindable var reader: ReaderModel
    @Environment(\.palette) private var palette
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(palette.tertiary)
                TextField("Search in this book", text: $reader.searchQuery)
                    .textFieldStyle(.plain)
                    .font(Typo.ui(14))
                    .focused($focused)
                    .onSubmit { reader.runSearch() }
                if reader.isSearching { ProgressView().controlSize(.small) }
            }
            .padding(14)
            Rectangle().fill(palette.rule).frame(height: 0.5)
            if reader.searchHits.isEmpty {
                Text(reader.isSearching ? "Searching…" : (reader.searchQuery.count < 2 ? "Type a word or phrase and press Return." : "No matches."))
                    .font(Typo.ui(12.5)).foregroundStyle(palette.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Text("\(reader.searchHits.count) match\(reader.searchHits.count == 1 ? "" : "es")")
                            .labelStyle(palette).padding(.horizontal, 16).padding(.vertical, 10)
                        ForEach(reader.searchHits) { hit in
                            Button { reader.go(to: hit.locator) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    if !hit.section.isEmpty {
                                        Text(hit.section).font(Typo.ui(10.5, weight: .medium)).foregroundStyle(palette.tertiary).lineLimit(1)
                                    }
                                    (Text(hit.before.suffix(60)) + Text(hit.match).bold().foregroundStyle(palette.accent) + Text(hit.after.prefix(80)))
                                        .font(Typo.serif(13))
                                        .foregroundStyle(palette.ink)
                                        .lineLimit(3)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(HoverTint())
                        }
                    }
                }
                .frame(maxHeight: 420)
            }
        }
        .frame(width: 380)
        .background(palette.raised)
        .onAppear { focused = true }
        .onDisappear { if reader.searchQuery.isEmpty { reader.endSearch() } }
    }
}

// MARK: - Appearance

struct AppearancePopover: View {
    let isPDF: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Theme").labelStyle(palette)
                HStack(spacing: 10) {
                    ForEach(ReaderTheme.allCases) { theme in
                        let p = theme.palette
                        Button {
                            app.settings.followsSystemAppearance = false
                            app.settings.theme = theme
                        } label: {
                            VStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(p.page)
                                    .frame(width: 82, height: 44)
                                    .overlay { Text("Aa").font(Typo.display(15)).foregroundStyle(p.ink) }
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(app.theme == theme ? palette.accent : palette.rule, lineWidth: app.theme == theme ? 2 : 0.5))
                                Text(theme.title).font(Typo.ui(10.5)).foregroundStyle(palette.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(theme.title) theme")
                        .accessibilityAddTraits(app.theme == theme ? .isSelected : [])
                    }
                }
                Toggle("Match the system's light and dark", isOn: $app.settings.followsSystemAppearance)
                    .toggleStyle(.checkbox)
                    .font(Typo.ui(12))
            }

            if !isPDF {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Text").labelStyle(palette)
                    Picker("Typeface", selection: $app.settings.font) {
                        ForEach(ReadingFont.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    HStack(spacing: 10) {
                        Image(systemName: "textformat.size.smaller").foregroundStyle(palette.secondary)
                        Slider(value: $app.settings.fontSize, in: 13...30, step: 1)
                        Image(systemName: "textformat.size.larger").foregroundStyle(palette.secondary)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "text.alignleft").foregroundStyle(palette.secondary).help("Line spacing")
                        Slider(value: $app.settings.lineHeight, in: 1.25...2.0, step: 0.05)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.left.and.right").foregroundStyle(palette.secondary).help("Line width")
                        Slider(value: $app.settings.maxLineWidth, in: 460...860, step: 20)
                    }
                    Toggle("Justify text", isOn: $app.settings.justify).toggleStyle(.checkbox).font(Typo.ui(12))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Pages").labelStyle(palette)
                Picker("Page turn", selection: $app.settings.pageTurn) {
                    ForEach(PageTurn.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Toggle("Two pages side by side when there is room", isOn: $app.settings.twoPages)
                    .toggleStyle(.checkbox).font(Typo.ui(12))
            }
        }
        .padding(18)
        .frame(width: 400)
        .background(palette.raised)
    }
}

// MARK: - Citation

/// Shown when a citation in a paper is clicked: the cited work, without leaving the page.
struct CitationCard: View {
    let reader: ReaderModel
    let lookup: CitationLookup
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Cited work").labelStyle(palette)
                Spacer()
                Button { reader.citation = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.tertiary)
                        .frame(width: 20, height: 20).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            if let paper = lookup.paper {
                Text(paper.title).font(Typo.display(15)).foregroundStyle(palette.ink).fixedSize(horizontal: false, vertical: true)
                Text(([paper.authors.count > 3 ? "\(paper.authors[0]) et al." : paper.authors.joined(separator: ", ")] + [paper.year.map(String.init), paper.venue].compactMap { $0 })
                    .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(Typo.ui(11.5)).foregroundStyle(palette.secondary).lineLimit(2)
                if let abstract = paper.abstract, !abstract.isEmpty {
                    ScrollView {
                        Text(abstract).font(Typo.serif(13)).lineSpacing(3).foregroundStyle(palette.ink)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 170)
                }
                HStack(spacing: 14) {
                    if paper.arxivID != nil || paper.doi != nil {
                        Button("Add to library") { reader.addCitedPaper() }
                    }
                    if let url = paper.landingURL {
                        Button("Open page") { NSWorkspace.shared.open(url) }
                    }
                }
                .buttonStyle(.plain)
                .font(Typo.ui(12, weight: .medium))
                .foregroundStyle(palette.accent)
            } else {
                Text(lookup.entry).font(Typo.serif(13)).lineSpacing(3).foregroundStyle(palette.ink)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if lookup.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking up the paper…").font(Typo.ui(12)).foregroundStyle(palette.secondary)
                    }
                } else {
                    Text("No matching paper was found online.").font(Typo.ui(12)).foregroundStyle(palette.tertiary)
                }
            }
        }
        .padding(14)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(palette.rule, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}

/// Offered when a book is reopened after some days away.
struct WelcomeBackCard: View {
    let reader: ReaderModel
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome back").font(Typo.display(15)).foregroundStyle(palette.ink)
                Text("It has been a while. Want a recap of the story so far?").font(Typo.ui(12)).foregroundStyle(palette.secondary)
            }
            Button { reader.recap() } label: {
                Text("Recap")
                    .font(Typo.ui(12.5, weight: .semibold)).foregroundStyle(palette.page)
                    .padding(.horizontal, 14).frame(height: 30)
                    .background(palette.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            Button { withAnimation { reader.showsWelcomeBack = false } } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.tertiary)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(palette.rule, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}
