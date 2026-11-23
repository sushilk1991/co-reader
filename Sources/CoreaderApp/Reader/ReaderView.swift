import CoreaderKit
import SwiftUI

struct ReaderView: View {
    @Bindable var reader: ReaderModel
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @AppStorage("reader.panelWidth") private var panelWidth: Double = 400

    var body: some View {
        VStack(spacing: 0) {
            if reader.isChromeVisible {
                ReaderTopBar(reader: reader)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ReadingArea(reader: reader)
                    if reader.isChromeVisible {
                        ReaderFooter(reader: reader)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                if let panel = reader.panel {
                    PanelDivider(width: $panelWidth)
                    Group {
                        switch panel {
                        case .notes: NotesPanel(reader: reader)
                        case .chat: ChatPanel(reader: reader, chat: reader.chat)
                        }
                    }
                    .frame(width: panelWidth)
                    .transition(.move(edge: .trailing))
                }
            }
        }
        .background(palette.page)
        .animation(.easeInOut(duration: 0.24), value: reader.panel)
        .background { shortcuts }
        .onChange(of: app.settings) { reader.settingsChanged() }
        .onChange(of: app.theme) { reader.settingsChanged() }
    }

    /// Keyboard shortcuts that must work wherever focus is.
    private var shortcuts: some View {
        Group {
            Button("") { reader.showsSearch.toggle() }.keyboardShortcut("f", modifiers: .command)
            Button("") { reader.showsContents.toggle() }.keyboardShortcut("t", modifiers: .command)
            Button("") { reader.panel = reader.panel == .notes ? nil : .notes }.keyboardShortcut("n", modifiers: [.command, .shift])
            Button("") { reader.panel = reader.panel == .chat ? nil : .chat; if reader.panel == .chat { reader.chat.focusComposer() } }.keyboardShortcut("l", modifiers: .command)
            Button("") { reader.toggleFocus() }.keyboardShortcut("f", modifiers: [.command, .shift])
            Button("") { reader.isSnipping = true }.keyboardShortcut("s", modifiers: [.command, .shift])
            Button("") { app.closeReader() }.keyboardShortcut("[", modifiers: .command)
            Button("") { reader.highlight(reader.lastColor) }.keyboardShortcut("h", modifiers: [.command, .shift])
            Button("") { reader.escape() }.keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}

// MARK: - Top bar

private struct ReaderTopBar: View {
    @Bindable var reader: ReaderModel
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            // Title is centred on the window, independent of the button groups.
            VStack(spacing: 1) {
                Text(reader.book.title)
                    .font(Typo.display(13, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                if !reader.chapter.isEmpty {
                    Text(reader.chapter)
                        .font(Typo.ui(11))
                        .foregroundStyle(palette.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 330)

            HStack(spacing: 4) {
                Button { app.closeReader() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                        Text("Library").font(Typo.ui(13))
                    }
                    .foregroundStyle(palette.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back to the library (⌘[)")
                .padding(.leading, 78)

                ChromeButton(symbol: "list.bullet", help: "Contents (⌘T)", isOn: reader.showsContents) { reader.showsContents.toggle() }
                    .popover(isPresented: $reader.showsContents, arrowEdge: .bottom) {
                        ContentsPopover(reader: reader).environment(\.palette, palette)
                    }

                Spacer()

                ChromeButton(symbol: "magnifyingglass", help: "Search in book (⌘F)", isOn: reader.showsSearch) { reader.showsSearch.toggle() }
                    .popover(isPresented: $reader.showsSearch, arrowEdge: .bottom) {
                        SearchPopover(reader: reader).environment(\.palette, palette)
                    }
                ChromeButton(symbol: "textformat.size", help: "Appearance", isOn: reader.showsAppearance) { reader.showsAppearance.toggle() }
                    .popover(isPresented: $reader.showsAppearance, arrowEdge: .bottom) {
                        AppearancePopover(isPDF: reader.pdf != nil).environment(app).environment(\.palette, palette)
                    }
                ChromeButton(symbol: "crop", help: "Snip an area into your notes (⇧⌘S)", isOn: reader.isSnipping) { reader.isSnipping.toggle() }
                ChromeButton(symbol: "circle.lefthalf.filled.righthalf.striped.horizontal", help: "Focus mode (⇧⌘F)") { reader.toggleFocus() }

                Rectangle().fill(palette.rule).frame(width: 0.5, height: 16).padding(.horizontal, 6)

                ChromeButton(symbol: "note.text", help: "Notes (⇧⌘N)", badge: 0, isOn: reader.panel == .notes) {
                    reader.panel = reader.panel == .notes ? nil : .notes
                }
                ChromeButton(symbol: "sparkles", help: "Ask AI (⌘L)", isOn: reader.panel == .chat) {
                    reader.panel = reader.panel == .chat ? nil : .chat
                }
            }
            .padding(.trailing, 14)
        }
        .frame(height: 52)
        .background(palette.page)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.rule.opacity(0.6)).frame(height: 0.5) }
    }
}

// MARK: - Footer

private struct ReaderFooter: View {
    @Bindable var reader: ReaderModel
    @Environment(\.palette) private var palette
    @State private var hoverFraction: Double?

    var body: some View {
        HStack(spacing: 14) {
            Text(reader.pageLabel.isEmpty ? " " : reader.pageLabel)
                .font(Typo.ui(11).monospacedDigit())
                .foregroundStyle(palette.tertiary)
                .frame(width: 130, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.rule).frame(height: 2)
                    Capsule().fill(palette.ink.opacity(0.55)).frame(width: max(2, geo.size.width * reader.fraction), height: 2)
                    if let h = hoverFraction {
                        Circle().fill(palette.ink).frame(width: 8, height: 8).offset(x: geo.size.width * h - 4)
                    }
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let p): hoverFraction = min(max(p.x / geo.size.width, 0), 1)
                    case .ended: hoverFraction = nil
                    }
                }
                .gesture(DragGesture(minimumDistance: 0).onEnded { value in
                    reader.go(toFraction: min(max(value.location.x / geo.size.width, 0), 1))
                })
                .help("Jump to a place in the book")
            }
            .frame(height: 20)
            .accessibilityElement()
            .accessibilityLabel("Position in book")
            .accessibilityValue("\(reader.fraction.percent) percent")

            Text(trailing)
                .font(Typo.ui(11).monospacedDigit())
                .foregroundStyle(palette.tertiary)
                .frame(width: 130, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .frame(height: 30)
        .background(palette.page)
    }

    private var trailing: String {
        let percent = "\(reader.fraction.percent)%"
        let book = reader.book
        guard book.secondsRead > 600, reader.fraction > 0.05, reader.fraction < 0.985 else { return percent }
        let left = book.secondsRead / reader.fraction * (1 - reader.fraction)
        let text = Duration.seconds(left).formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 1))
        return "\(text) left · \(percent)"
    }
}

// MARK: - Reading area

private struct ReadingArea: View {
    @Bindable var reader: ReaderModel
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                palette.page

                if let web = reader.web {
                    WebReaderView(controller: web)
                        .opacity(reader.isLoading ? 0 : 1)
                } else if let pdf = reader.pdf {
                    PDFReaderView(controller: pdf)
                        .opacity(reader.isLoading ? 0 : 1)
                        .onChange(of: geo.size.width, initial: true) { pdf.setAvailableWidth(geo.size.width) }
                }

                if let turn = reader.turn {
                    PageTurnLeaf(turn: turn, size: geo.size) { reader.turn = nil }
                        .id(turn.id)
                }

                if reader.web != nil, !reader.isSnipping, app.settings.pageTurn != .scroll {
                    EdgeArrows(reader: reader)
                }

                if reader.isLoading {
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.small)
                        Text("Opening \(reader.book.title)…").font(Typo.ui(12)).foregroundStyle(palette.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let error = reader.loadError {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 22)).foregroundStyle(palette.accent)
                        Text("This book could not be opened").font(Typo.display(18)).foregroundStyle(palette.ink)
                        Text(error).font(Typo.ui(12.5)).foregroundStyle(palette.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
                        Button("Show File in Finder") { app.revealInFinder(reader.entry.id) }.padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if let selection = reader.selection, reader.glance == nil, !reader.isSnipping {
                    SelectionBar(reader: reader)
                        .floating(near: selection.rect, in: geo.size, size: CGSize(width: 452, height: 40))
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                if let glance = reader.glance {
                    GlanceCard(reader: reader, glance: glance)
                        .floating(near: glance.selection.rect, in: geo.size, size: CGSize(width: 360, height: 190), prefersBelow: true)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                if let active = reader.activeAnnotation, let annotation = reader.annotations.first(where: { $0.id == active.id }) {
                    AnnotationCard(reader: reader, annotation: annotation)
                        .floating(near: active.rect, in: geo.size, size: CGSize(width: 340, height: 200), prefersBelow: true)
                        .id(active.id)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                if let lookup = reader.citation {
                    CitationCard(reader: reader, lookup: lookup)
                        .floating(near: lookup.rect, in: geo.size, size: CGSize(width: 380, height: 260), prefersBelow: true)
                        .id(lookup.id)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                if reader.showsWelcomeBack, !reader.isLoading {
                    WelcomeBackCard(reader: reader)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 26)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if reader.isSnipping {
                    SnipOverlay(onSnip: { rect, copy in reader.snip(rect, copyToClipboard: copy) }, onCancel: { reader.isSnipping = false })
                }

                if reader.showsFinishCard {
                    FinishCard(reader: reader)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 26)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if reader.isFocusMode, !reader.isChromeVisible {
                    // A way back that does not rely on knowing the shortcut.
                    FocusExit(since: reader.openedAt) { reader.toggleFocus() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(14)
                }
            }
            .animation(.easeOut(duration: 0.14), value: reader.selection)
            .animation(.easeOut(duration: 0.16), value: reader.glance?.id)
            .animation(.easeOut(duration: 0.16), value: reader.activeAnnotation)
            .clipped()
        }
    }
}

private struct FocusExit: View {
    let since: Date
    let action: () -> Void
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // Minutes in this sitting: enough to notice time, too coarse to nag.
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("\(max(0, Int(context.date.timeIntervalSince(since) / 60))) min")
                        .font(Typo.ui(11).monospacedDigit())
                        .foregroundStyle(palette.secondary)
                }
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(palette.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(palette.rule, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .opacity(hovering ? 1 : 0.25)
        .onHover { hovering = $0 }
        .help("Leave focus mode (Esc)")
        .accessibilityLabel("Leave focus mode")
    }
}

/// Previous/next affordances that appear when the pointer nears a page edge.
private struct EdgeArrows: View {
    let reader: ReaderModel
    @Environment(\.palette) private var palette
    @State private var hover: Edge?

    var body: some View {
        HStack(spacing: 0) {
            arrow(.leading, symbol: "chevron.left", label: "Previous page") { reader.previousPage() }
            Spacer().allowsHitTesting(false)
            arrow(.trailing, symbol: "chevron.right", label: "Next page") { reader.nextPage() }
        }
    }

    private func arrow(_ edge: Edge, symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(palette.secondary)
                .frame(width: 34, height: 34)
                .background(palette.raised.opacity(0.9), in: Circle())
                .overlay(Circle().strokeBorder(palette.rule, lineWidth: 0.5))
                .opacity(hover == edge ? 1 : 0)
                .frame(width: 44)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 ? edge : (hover == edge ? nil : hover) }
        .animation(.easeOut(duration: 0.15), value: hover)
        .accessibilityLabel(label)
    }
}

/// The page being left, lifted off the spine and turned away.
private struct PageTurnLeaf: View {
    let turn: ReaderModel.TurningPage
    let size: CGSize
    let done: () -> Void
    @State private var progress: Double = 0

    var body: some View {
        Image(nsImage: turn.image)
            .resizable()
            .frame(width: size.width, height: size.height)
            .background(Color.clear)
            .overlay {
                // Light falls off across the lifting page.
                LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.28 * progress)],
                               startPoint: turn.forward ? .leading : .trailing,
                               endPoint: turn.forward ? .trailing : .leading)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.25 * (1 - progress)), radius: 18, x: turn.forward ? -8 : 8)
            .rotation3DEffect(.degrees((turn.forward ? -1 : 1) * 88 * progress),
                              axis: (x: 0, y: 1, z: 0),
                              anchor: turn.forward ? .leading : .trailing,
                              perspective: 0.35)
            .opacity(1 - pow(progress, 3))
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeIn(duration: 0.38)) { progress = 1 } completion: { done() }
            }
    }
}

private struct PanelDivider: View {
    @Binding var width: Double
    @Environment(\.palette) private var palette
    @State private var start: Double?

    var body: some View {
        Rectangle()
            .fill(palette.rule.opacity(0.8))
            .frame(width: 0.5)
            .overlay {
                Color.clear.frame(width: 9).contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            let base = start ?? width
                            start = base
                            width = min(max(base - value.translation.width, 300), 640)
                        }
                        .onEnded { _ in start = nil })
            }
            .accessibilityHidden(true)
    }
}

extension View {
    /// Places a floating card beside a rectangle of the page, keeping it inside the area.
    func floating(near rect: CGRect, in area: CGSize, size: CGSize, prefersBelow: Bool = false) -> some View {
        let gap: CGFloat = 10
        let fitsAbove = rect.minY - size.height - gap > 8
        let fitsBelow = rect.maxY + size.height + gap < area.height - 8
        let below = prefersBelow ? (fitsBelow || !fitsAbove) : !fitsAbove
        var y = below ? rect.maxY + gap : rect.minY - size.height - gap
        y = min(max(y, 8), max(8, area.height - size.height - 8))
        let x = min(max(rect.midX - size.width / 2, 12), max(12, area.width - size.width - 12))
        return self
            .frame(width: size.width, alignment: .center)
            .frame(minHeight: below ? nil : size.height, alignment: .bottom)
            .offset(x: x, y: y)
    }
}
