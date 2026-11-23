import AppKit
import CoreaderKit
import SwiftUI
import UniformTypeIdentifiers

/// Every highlight, note and saved image in the library on one page: browse by book,
/// narrow by kind, colour or words, edit a note in place, jump back into the book.
struct NotebookView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var notebook = app.notebook
        let visible = notebook.query.apply(to: notebook.notes)
        VStack(spacing: 0) {
            header(visible)
            if notebook.hasLoaded, notebook.notes.isEmpty {
                empty
            } else {
                HStack(spacing: 0) {
                    NotebookSidebar(notebook: notebook)
                        .frame(width: 252)
                    Rectangle().fill(palette.rule.opacity(0.7)).frame(width: 0.5)
                    NotebookList(notebook: notebook, visible: visible)
                }
            }
        }
        .background(palette.surface)
        .onAppear { notebook.reload(app: app) }
    }

    private func header(_ visible: [LibraryNote]) -> some View {
        @Bindable var notebook = app.notebook
        return ZStack {
            Text("Notebook")
                .font(.system(size: 17, weight: .semibold, design: .serif))
                .foregroundStyle(palette.ink)

            HStack(spacing: 0) {
                Button { app.closeNotebook() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("Library").font(Typo.ui(13))
                    }
                    .foregroundStyle(palette.secondary)
                    .padding(.horizontal, 8).frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Back to the library")
                .background {
                    // Escape goes back, except while a note is being typed: there it cancels the edit.
                    if notebook.editing == nil {
                        Button("") { app.closeNotebook() }.keyboardShortcut(.cancelAction).opacity(0)
                    }
                }
                .padding(.leading, 78)

                Spacer(minLength: 24)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.tertiary)
                    TextField("Search notes", text: $notebook.query.text)
                        .textFieldStyle(.plain)
                        .font(Typo.ui(13))
                        .foregroundStyle(palette.ink)
                        .focused($searchFocused)
                        .frame(width: 190)
                    if !notebook.query.text.isEmpty {
                        Button { notebook.query.text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(palette.tertiary) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(palette.raised.opacity(0.8), in: Capsule())
                .overlay(Capsule().strokeBorder(palette.rule, lineWidth: 0.5))
                .padding(.trailing, 8)

                Menu {
                    Button("Copy \(visible.count == notebook.notes.count ? "All" : "These") as Markdown") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(notebook.markdown(visible), forType: .string)
                        app.show("\(visible.count) \(visible.count == 1 ? "note" : "notes") copied as Markdown.")
                    }
                    Button("Export as Markdown…") { export(visible) }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .disabled(visible.isEmpty)
                .help("Copy or export the notes shown")
                .accessibilityLabel("Copy or export")
                .padding(.trailing, 20)
            }
        }
        .frame(height: 54)
        .background(palette.surface)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.rule.opacity(0.7)).frame(height: 0.5) }
        .background {
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).opacity(0)
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "text.quote").font(.system(size: 30, weight: .light)).foregroundStyle(palette.tertiary)
            Text("Nothing in the notebook yet").font(Typo.display(22)).foregroundStyle(palette.ink)
            Text("Highlights, notes and images you keep while reading gather here, from every book.\nOpen a book, select a passage and pick a colour to make the first one.")
                .font(Typo.ui(13)).foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center).lineSpacing(4)
            Button("Back to Library") { app.closeNotebook() }
                .buttonStyle(.plain)
                .font(Typo.ui(13, weight: .medium)).foregroundStyle(palette.accent)
                .padding(.top, 6)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func export(_ visible: [LibraryNote]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "Reading notes.md"
        let text = app.notebook.markdown(visible)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            app.show("Exported \(visible.count) \(visible.count == 1 ? "note" : "notes").")
        } catch {
            app.show("Could not export: \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - Sidebar

private struct NotebookSidebar: View {
    @Bindable var notebook: NotebookModel
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                row(symbol: "tray.full", title: "All notes", count: notebook.notes.count,
                    isOn: notebook.query.kind == nil && notebook.query.bookID == nil && notebook.query.color == nil) {
                    notebook.query.kind = nil
                    notebook.query.bookID = nil
                    notebook.query.color = nil
                }

                section("Show")
                kind(.highlights, "highlighter", "Highlights")
                kind(.notes, "square.and.pencil", "With my notes")
                kind(.images, "photo", "Images")

                let colors = HighlightColor.allCases.filter { c in notebook.notes.contains { $0.annotation.kind == .highlight && $0.annotation.color == c } }
                if colors.count > 1 {
                    section("Colour")
                    HStack(spacing: 12) {
                        ForEach(colors, id: \.self) { color in
                            let isOn = notebook.query.color == color
                            Button { notebook.query.color = isOn ? nil : color } label: {
                                Circle().fill(color.color).frame(width: 14, height: 14)
                                    .overlay { if isOn { Circle().strokeBorder(palette.ink.opacity(0.65), lineWidth: 1.5).padding(-3.5) } }
                                    .opacity(notebook.query.color == nil || isOn ? 1 : 0.35)
                                    .frame(width: 22, height: 22)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Only \(color.rawValue) highlights")
                            .accessibilityLabel("\(color.rawValue) highlights")
                            .accessibilityAddTraits(isOn ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                }

                section("Books")
                ForEach(NotebookQuery.books(in: notebook.notes), id: \.entry.id) { item in
                    let isOn = notebook.query.bookID == item.entry.id
                    Button { notebook.query.bookID = isOn ? nil : item.entry.id } label: {
                        HStack(spacing: 10) {
                            BookCover(entry: item.entry, width: 22)
                            Text(item.entry.book.title)
                                .font(Typo.ui(12.5, weight: isOn ? .semibold : .regular))
                                .foregroundStyle(isOn ? palette.ink : palette.secondary)
                                .lineLimit(2).multilineTextAlignment(.leading)
                            Spacer(minLength: 6)
                            Text("\(item.count)").font(Typo.ui(11).monospacedDigit()).foregroundStyle(palette.tertiary)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(isOn ? palette.ink.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(item.entry.book.title), \(item.count) notes")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .scrollContentBackground(.hidden)
    }

    private func section(_ title: String) -> some View {
        Text(title).labelStyle(palette)
            .padding(.horizontal, 10).padding(.top, 20).padding(.bottom, 6)
    }

    private func kind(_ kind: NotebookQuery.Kind, _ symbol: String, _ title: String) -> some View {
        let isOn = notebook.query.kind == kind
        return row(symbol: symbol, title: title, count: notebook.count(kind), isOn: isOn) {
            notebook.query.kind = isOn ? nil : kind
        }
    }

    private func row(symbol: String, title: String, count: Int, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 12)).frame(width: 18)
                    .foregroundStyle(isOn ? palette.accent : palette.tertiary)
                Text(title).font(Typo.ui(13, weight: isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? palette.ink : palette.secondary)
                Spacer(minLength: 6)
                Text("\(count)").font(Typo.ui(11).monospacedDigit()).foregroundStyle(palette.tertiary)
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(isOn ? palette.ink.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

// MARK: - List

private struct NotebookList: View {
    @Bindable var notebook: NotebookModel
    let visible: [LibraryNote]
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    private struct Group: Identifiable {
        var id: String
        /// Set when the group is one book; nil for a day.
        var entry: BookEntry?
        var title: String
        var notes: [LibraryNote]
    }

    private var groups: [Group] {
        var out: [Group] = []
        let byBook = notebook.query.sort == .book
        let calendar = Calendar.current
        for note in visible {
            let key = byBook ? note.entry.id : "\(calendar.startOfDay(for: note.annotation.createdAt).timeIntervalSince1970)"
            if let last = out.indices.last, out[last].id == key {
                out[last].notes.append(note)
            } else {
                out.append(Group(id: key, entry: byBook ? note.entry : nil,
                                 title: byBook ? note.entry.book.title : Self.day(note.annotation.createdAt, calendar), notes: [note]))
            }
        }
        return out
    }

    private static func day(_ date: Date, _ calendar: Calendar) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                toolbar
                if visible.isEmpty, notebook.hasLoaded {
                    noMatches
                }
                ForEach(groups) { group in
                    heading(group)
                    ForEach(Array(group.notes.enumerated()), id: \.element.id) { index, note in
                        // In a book the chapter is named once, above its first note.
                        if group.entry != nil, let chapter = note.annotation.chapter, !chapter.isEmpty,
                           index == 0 || group.notes[index - 1].annotation.chapter != chapter {
                            Text(chapter).labelStyle(palette)
                                .padding(.top, index == 0 ? 4 : 18).padding(.bottom, 8).padding(.leading, 2)
                        }
                        NotebookRow(notebook: notebook, note: note, showsBook: group.entry == nil)
                            .padding(.bottom, 10)
                    }
                }
            }
            .padding(.horizontal, 44)
            .padding(.top, 26)
            .padding(.bottom, 72)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(palette.surface)
    }

    private var toolbar: some View {
        let selected = notebook.query.bookID.flatMap { id in notebook.notes.first { $0.entry.id == id }?.entry }
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(selected?.book.title ?? "All notes")
                .font(Typo.display(24)).foregroundStyle(palette.ink).lineLimit(1)
            Text(notebook.query.isFiltering && visible.count != notebook.notes.count
                 ? "\(visible.count) of \(notebook.notes.count)" : "\(visible.count)")
                .font(Typo.ui(13).monospacedDigit()).foregroundStyle(palette.tertiary)
            if notebook.query.isFiltering {
                Button("Clear filters") { clear() }
                    .buttonStyle(.plain)
                    .font(Typo.ui(12, weight: .medium)).foregroundStyle(palette.accent)
                    .padding(.leading, 4)
            }
            Spacer(minLength: 12)
            HStack(spacing: 2) {
                FilterChip(title: "By book", isOn: notebook.query.sort == .book) { notebook.query.sort = .book }
                FilterChip(title: "Newest", isOn: notebook.query.sort == .newest) { notebook.query.sort = .newest }
                FilterChip(title: "Oldest", isOn: notebook.query.sort == .oldest) { notebook.query.sort = .oldest }
            }
        }
        .padding(.bottom, 8)
    }

    private func clear() {
        let sort = notebook.query.sort
        notebook.query = NotebookQuery()
        notebook.query.sort = sort
    }

    @ViewBuilder
    private func heading(_ group: Group) -> some View {
        if let entry = group.entry {
            HStack(spacing: 14) {
                BookCover(entry: entry, width: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.book.title).font(Typo.display(17)).foregroundStyle(palette.ink).lineLimit(2)
                    Text([entry.book.shortAuthors, "\(group.notes.count) \(group.notes.count == 1 ? "note" : "notes")"].filter { !$0.isEmpty }.joined(separator: "  ·  "))
                        .font(Typo.ui(12)).foregroundStyle(palette.tertiary).lineLimit(1)
                }
                Spacer(minLength: 12)
                Button { app.open(entry.id) } label: {
                    HStack(spacing: 4) {
                        Text("Open book")
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                    }
                    .font(Typo.ui(12, weight: .medium)).foregroundStyle(palette.accent)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 30).padding(.bottom, 16)
        } else {
            Text(group.title).font(Typo.display(15)).foregroundStyle(palette.secondary)
                .padding(.top, 28).padding(.bottom, 12).padding(.leading, 2)
        }
    }

    private var noMatches: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing matches").font(Typo.display(18)).foregroundStyle(palette.ink)
            Text("No note fits these filters\(notebook.query.text.isEmpty ? "" : " and “\(notebook.query.text)”").")
                .font(Typo.ui(13)).foregroundStyle(palette.secondary)
            Button("Clear filters") { clear() }
                .buttonStyle(.plain)
                .font(Typo.ui(13, weight: .medium)).foregroundStyle(palette.accent)
                .padding(.top, 4)
        }
        .padding(.top, 48)
    }
}

// MARK: - One note

private struct NotebookRow: View {
    let notebook: NotebookModel
    let note: LibraryNote
    /// Name the book on the row: needed when the list is not grouped by book.
    let showsBook: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var hovering = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var a: Annotation { note.annotation }
    private var isEditing: Bool { notebook.editing == note.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if a.kind == .image {
                if let asset = a.asset { NoteImage(url: note.entry.assetsURL.appendingPathComponent(asset)) }
                if !a.quote.isEmpty {
                    Text(a.quote).font(Typo.ui(12.5)).foregroundStyle(palette.secondary).textSelection(.enabled)
                }
            } else if !a.quote.isEmpty {
                Text(a.quote)
                    .font(Typo.serif(16.5))
                    .lineSpacing(5)
                    .foregroundStyle(palette.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 16)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5).fill(a.color.color).frame(width: 3)
                    }
            }

            if isEditing {
                editor
            } else if !a.note.isEmpty {
                MarkdownText(text: a.note, baseSize: a.quote.isEmpty ? 14.5 : 13.5)
                    .padding(.leading, a.quote.isEmpty || a.kind == .image ? 0 : 16)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { begin() }
                    .help("Double-click to edit")
            }

            footer
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.raised.opacity(hovering || isEditing ? 1 : 0.72), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(isEditing ? palette.accent.opacity(0.45) : palette.rule.opacity(0.8), lineWidth: isEditing ? 1 : 0.5))
        .onHover { hovering = $0 }
        .contextMenu { menu }
    }

    private var editor: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextEditor(text: $draft)
                .font(Typo.ui(13.5))
                .foregroundStyle(palette.ink)
                .scrollContentBackground(.hidden)
                .focused($focused)
                .frame(minHeight: 72)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .background(palette.page, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.rule, lineWidth: 0.5))
                .accessibilityLabel("Note")
            HStack(spacing: 14) {
                Text("Markdown works here").font(Typo.ui(11)).foregroundStyle(palette.tertiary)
                Spacer()
                Button("Cancel") { notebook.editing = nil }
                    .buttonStyle(.plain)
                    .font(Typo.ui(12.5)).foregroundStyle(palette.secondary)
                    .keyboardShortcut(.cancelAction)
                Button { commit() } label: {
                    Text("Save")
                        .font(Typo.ui(12.5, weight: .semibold)).foregroundStyle(palette.page)
                        .padding(.horizontal, 14).frame(height: 26)
                        .background(palette.ink, in: Capsule())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Save (⌘↩)")
            }
        }
        .padding(.leading, a.quote.isEmpty || a.kind == .image ? 0 : 16)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button { open() } label: {
                HStack(spacing: 5) {
                    Text(place).lineLimit(1)
                    Image(systemName: "arrow.up.right").font(.system(size: 8.5, weight: .semibold))
                }
                .font(Typo.ui(11.5, weight: .medium))
                .foregroundStyle(hovering ? palette.accent : palette.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open this place in the book")

            Text("·").foregroundStyle(palette.tertiary)
            Text(a.createdAt.formatted(.dateTime.day().month(.abbreviated).year()))
                .font(Typo.ui(11.5)).foregroundStyle(palette.tertiary).lineLimit(1)

            Spacer(minLength: 10)

            if !isEditing {
                HStack(spacing: 2) {
                    action("square.and.pencil", a.note.isEmpty ? "Add a note" : "Edit note") { begin() }
                    action("doc.on.doc", "Copy as Markdown") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(NotebookModel.markdown(for: note), forType: .string)
                        app.show("Copied.")
                    }
                    action("trash", "Remove") { notebook.remove(note, app: app) }
                }
                .opacity(hovering ? 1 : 0.55)
            }
        }
        .frame(height: 26)
    }

    private func action(_ symbol: String, _ label: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var menu: some View {
        Button("Open in Book") { open() }
        Button(a.note.isEmpty ? "Add a Note" : "Edit Note") { begin() }
        Button("Copy as Markdown") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(NotebookModel.markdown(for: note), forType: .string)
        }
        if a.kind == .highlight {
            Menu("Colour") {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    Button {
                        notebook.apply(.color(color), to: note, app: app)
                    } label: {
                        if a.color == color { Label(color.rawValue.capitalized, systemImage: "checkmark") } else { Text(color.rawValue.capitalized) }
                    }
                }
            }
        }
        if a.kind == .image, let asset = a.asset {
            Button("Show Image in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([note.entry.assetsURL.appendingPathComponent(asset)])
            }
        }
        Divider()
        Button("Remove", role: .destructive) { notebook.remove(note, app: app) }
    }

    /// "Walden · Economy" or "Economy · p. 12": the book only when the list is by date.
    private var place: String {
        let position = NotesDocument.positionLabel(for: a.locator)
        var parts: [String] = []
        if showsBook { parts.append(note.entry.book.title) }
        if let chapter = a.chapter, !chapter.isEmpty, chapter != position, showsBook || a.locator.page != nil { parts.append(chapter) }
        parts.append(position)
        return parts.joined(separator: "  ·  ")
    }

    private func open() {
        app.open(note.entry.id, at: .annotation(bookID: note.entry.id, annotationID: a.id))
    }

    private func begin() {
        draft = a.note
        notebook.editing = note.id
        focused = true
    }

    private func commit() {
        notebook.editing = nil
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // A bare note with nothing written is not worth keeping.
        if text.isEmpty, a.kind == .note { notebook.remove(note, app: app, offersUndo: !a.note.isEmpty); return }
        if text != a.note { notebook.apply(.note(text), to: note, app: app) }
    }
}

/// A saved figure or snip, decoded off the main thread at the size it is shown.
private struct NoteImage: View {
    let url: URL
    @Environment(\.palette) private var palette
    @Environment(\.displayScale) private var displayScale
    @State private var image: NSImage?
    @State private var missing = false

    private var maxPixel: Int { Int(760 * displayScale) }

    var body: some View {
        let shown = image ?? CoverCache.shared.cached(for: url, version: 0, maxPixel: maxPixel)
        Group {
            if let shown {
                Image(nsImage: shown)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: min(shown.size.width / displayScale, 760), maxHeight: 380, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(palette.rule, lineWidth: 0.5))
                    .onDrag { NSItemProvider(object: url as NSURL) }
                    .accessibilityLabel("Saved image")
            } else {
                HStack(spacing: 8) {
                    Image(systemName: missing ? "photo.badge.exclamationmark" : "photo")
                    Text(missing ? "The image file is missing or still downloading from iCloud." : "Loading image…")
                }
                .font(Typo.ui(12)).foregroundStyle(palette.tertiary)
                .frame(maxWidth: .infinity, minHeight: 90)
                .background(palette.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .task(id: url) {
            image = await CoverCache.shared.image(for: url, version: 0, maxPixel: maxPixel)
            missing = image == nil
        }
    }
}
