import AppKit
import CoreaderKit
import SwiftUI

/// The notebook for the open book: every highlight, note and saved image in reading
/// order. It is a view of `notes.md`; nothing here exists anywhere else.
struct NotesPanel: View {
    @Bindable var reader: ReaderModel
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var filter: HighlightColor?
    @State private var onlyNotes = false

    private var visible: [Annotation] {
        reader.annotations.filter { a in
            if let filter, a.color != filter || a.kind == .image { return false }
            if onlyNotes, a.note.isEmpty { return false }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if reader.annotations.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let groups = grouped(visible)
                        ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                            if !group.chapter.isEmpty {
                                Text(group.chapter)
                                    .labelStyle(palette)
                                    .padding(.horizontal, 20)
                                    .padding(.top, 20)
                                    .padding(.bottom, 6)
                            }
                            ForEach(group.items) { annotation in
                                NoteRow(reader: reader, annotation: annotation)
                            }
                        }
                        if visible.isEmpty {
                            Text("Nothing matches this filter.")
                                .font(Typo.ui(12.5)).foregroundStyle(palette.secondary)
                                .padding(20)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .background(palette.surface)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Notes").font(Typo.display(16)).foregroundStyle(palette.ink)
                Text("\(reader.annotations.count)").font(Typo.ui(12).monospacedDigit()).foregroundStyle(palette.tertiary)
                Spacer()
                Menu {
                    Button("Copy All as Markdown") { copyMarkdown() }
                    Button("Open notes.md") { NSWorkspace.shared.open(reader.entry.notesURL) }
                    Button("Show in Finder") { app.revealInFinder(reader.entry.id) }
                    Divider()
                    Button("Add Note at This Page") {
                        reader.addNote("")
                        if let last = reader.annotations.last(where: { $0.kind == .note && $0.note.isEmpty }) { NotesFocus.shared.request(last.id) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.system(size: 14)).foregroundStyle(palette.secondary)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Notes actions")
                Button { reader.panel = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.tertiary)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close notes")
            }
            if !reader.annotations.isEmpty {
                HStack(spacing: 8) {
                    ForEach(HighlightColor.allCases, id: \.self) { color in
                        let count = reader.annotations.filter { $0.color == color && $0.kind != .image }.count
                        if count > 0 {
                            Button { filter = filter == color ? nil : color } label: {
                                Circle().fill(color.color).frame(width: 12, height: 12)
                                    .overlay { if filter == color { Circle().strokeBorder(palette.ink.opacity(0.6), lineWidth: 1.5).padding(-3) } }
                                    .opacity(filter == nil || filter == color ? 1 : 0.35)
                            }
                            .buttonStyle(.plain)
                            .help("Only \(color.rawValue) highlights")
                            .accessibilityLabel("Filter \(color.rawValue)")
                        }
                    }
                    Spacer()
                    Button { onlyNotes.toggle() } label: {
                        Text("With notes")
                            .font(Typo.ui(11, weight: onlyNotes ? .semibold : .regular))
                            .foregroundStyle(onlyNotes ? palette.ink : palette.secondary)
                            .padding(.horizontal, 8).frame(height: 22)
                            .background(onlyNotes ? palette.ink.opacity(0.08) : .clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.rule.opacity(0.7)).frame(height: 0.5) }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "highlighter").font(.system(size: 24, weight: .light)).foregroundStyle(palette.tertiary)
            Text("No notes yet").font(Typo.display(17)).foregroundStyle(palette.ink)
            Text("Select a passage to highlight it or write a note. Right-click a figure to keep it, or snip any area of the page.\n\nEverything is saved as Markdown in this book's folder.")
                .font(Typo.ui(12.5)).foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center).lineSpacing(3)
                .frame(maxWidth: 270)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func grouped(_ list: [Annotation]) -> [(chapter: String, items: [Annotation])] {
        var out: [(chapter: String, items: [Annotation])] = []
        for a in list {
            let chapter = a.chapter ?? ""
            if let last = out.indices.last, out[last].chapter == chapter { out[last].items.append(a) }
            else { out.append((chapter, [a])) }
        }
        return out
    }

    private func copyMarkdown() {
        let text = (try? String(contentsOf: reader.entry.notesURL, encoding: .utf8)) ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        app.show("Notes copied as Markdown.")
    }
}

private struct NoteRow: View {
    let reader: ReaderModel
    let annotation: Annotation
    @Environment(\.palette) private var palette
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if annotation.kind == .image, let url = reader.assetURL(annotation), let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(palette.rule, lineWidth: 0.5))
                    .onDrag { NSItemProvider(object: url as NSURL) }
                if !annotation.quote.isEmpty {
                    Text(annotation.quote).font(Typo.ui(11.5)).foregroundStyle(palette.secondary).lineLimit(3)
                }
            } else if !annotation.quote.isEmpty {
                Text(annotation.quote)
                    .font(Typo.serif(14))
                    .lineSpacing(3.5)
                    .foregroundStyle(palette.ink)
                    .textSelection(.enabled)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1.5).fill(annotation.color.color).frame(width: 3)
                    }
            }

            if editing {
                TextEditor(text: $draft)
                    .font(Typo.ui(13))
                    .foregroundStyle(palette.ink)
                    .scrollContentBackground(.hidden)
                    .focused($focused)
                    .frame(minHeight: 54)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(6)
                    .background(palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(palette.accent.opacity(0.5), lineWidth: 1))
                    .onChange(of: focused) { if !focused { commit() } }
            } else if !annotation.note.isEmpty {
                MarkdownText(text: annotation.note, baseSize: 13)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { beginEditing() }
            }

            HStack(spacing: 10) {
                Button { reader.go(to: annotation.locator) } label: {
                    Text(annotation.locator.label ?? "\(Int(annotation.locator.fraction * 100))%")
                        .font(Typo.ui(10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(palette.tertiary)
                }
                .buttonStyle(.plain)
                .help("Go to this place in the book")
                Spacer()
                if hovering || editing {
                    Group {
                        if !editing {
                            Button { beginEditing() } label: { Image(systemName: "square.and.pencil") }
                                .help(annotation.note.isEmpty ? "Add a note" : "Edit note")
                                .accessibilityLabel("Edit note")
                        }
                        Button { copy() } label: { Image(systemName: "doc.on.doc") }
                            .help("Copy as Markdown")
                            .accessibilityLabel("Copy as Markdown")
                        Button { reader.remove(annotation.id) } label: { Image(systemName: "trash") }
                            .help("Remove")
                            .accessibilityLabel("Remove")
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.secondary)
                }
            }
            .frame(height: 14)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(hovering ? palette.ink.opacity(0.03) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if !editing { reader.go(to: annotation.locator) } }
        .overlay(alignment: .bottom) { Rectangle().fill(palette.rule.opacity(0.5)).frame(height: 0.5).padding(.leading, 20) }
        .onAppear {
            if NotesFocus.shared.requested == annotation.id {
                NotesFocus.shared.requested = nil
                beginEditing()
            }
        }
        .onChange(of: NotesFocus.shared.requested) {
            if NotesFocus.shared.requested == annotation.id {
                NotesFocus.shared.requested = nil
                beginEditing()
            }
        }
    }

    private func beginEditing() {
        draft = annotation.note
        editing = true
        focused = true
    }

    private func commit() {
        editing = false
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        // A bare note with nothing written is not worth keeping.
        if text.isEmpty, annotation.kind == .note { reader.remove(annotation.id); return }
        if text != annotation.note { reader.update(annotation.id) { $0.note = text } }
    }

    private func copy() {
        var parts: [String] = []
        if !annotation.quote.isEmpty { parts.append(annotation.quote.split(separator: "\n").map { "> \($0)" }.joined(separator: "\n")) }
        if !annotation.note.isEmpty { parts.append(annotation.note) }
        let link = DeepLink.annotation(bookID: reader.entry.id, annotationID: annotation.id).url.absoluteString
        parts.append("— *\(reader.book.title)*, [\(annotation.locator.label ?? "open")](\(link))")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(parts.joined(separator: "\n\n"), forType: .string)
    }
}
