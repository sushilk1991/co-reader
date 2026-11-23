import AppKit
import CoreaderKit
import SwiftUI

/// Every highlight, note and saved image in the library, for the notebook screen. Like
/// the notes panel it is a view of the `notes.md` files: edits go to the file through
/// `WriteQueue` and nothing is stored anywhere else.
@MainActor
@Observable
final class NotebookModel {
    var notes: [LibraryNote] = []
    var query = NotebookQuery()
    var hasLoaded = false
    /// `LibraryNote.id` of the row whose note is being typed.
    var editing: String?

    func reload(app: AppModel) {
        let library = app.library, store = app.notes
        Task {
            // Behind writes still queued, so an edit made a moment ago is in what is read.
            await WriteQueue.shared.drain()
            let loaded = try? await offMain { try store.all(in: library).map { LibraryNote(entry: $0.entry, annotation: $0.annotation) } }
            if let loaded { notes = loaded }
            hasLoaded = true
            // A filter for a book that has no notes left would show an empty page.
            if let id = query.bookID, !notes.contains(where: { $0.entry.id == id }) { query.bookID = nil }
        }
    }

    func count(_ kind: NotebookQuery.Kind) -> Int {
        var only = NotebookQuery()
        only.kind = kind
        return notes.count(where: only.matches)
    }

    // MARK: Changes

    func apply(_ edit: AnnotationEdit, to note: LibraryNote, app: AppModel) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        edit.apply(to: &notes[index].annotation)
        let store = app.notes, entry = note.entry, id = note.annotation.id
        WriteQueue.shared.enqueue(WriteQueue.notes(entry.id), {
            // Applied to the annotation as it is in the file now, so text changed in
            // another app since the notebook loaded is kept.
            if try store.update(id: id, in: entry, { edit.apply(to: &$0) }) == nil { throw Gone() }
        }) { [weak self] error in
            app.show(error is Gone ? "That note is no longer in the notes file." : "Could not write to the notes file: \(error.localizedDescription)", isError: true)
            self?.reload(app: app)
        }
    }

    /// Takes the note out of its file, and offers to put it back for a few seconds.
    func remove(_ note: LibraryNote, app: AppModel, offersUndo: Bool = true) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        // As it is now, not as the row captured it: it may have been edited since.
        let removed = notes.remove(at: index)
        if offersUndo {
            let what = removed.annotation.kind == .image ? "Image" : removed.annotation.kind == .note ? "Note" : "Highlight"
            app.show("\(what) removed from “\(removed.entry.book.title)”.", actionTitle: "Undo") { [weak self] in
                self?.restore(removed, at: index, app: app)
            }
        }
        if query.bookID == note.entry.id, !notes.contains(where: { $0.entry.id == note.entry.id }) { query.bookID = nil }
        let store = app.notes, entry = note.entry, id = note.annotation.id
        WriteQueue.shared.enqueue(WriteQueue.notes(entry.id), { try store.remove(id: id, from: entry) }) { [weak self] error in
            app.show("Could not write to the notes file: \(error.localizedDescription)", isError: true)
            self?.reload(app: app)
        }
    }

    private func restore(_ note: LibraryNote, at index: Int, app: AppModel) {
        guard !notes.contains(where: { $0.id == note.id }) else { return }
        notes.insert(note, at: min(index, notes.count))
        let store = app.notes
        WriteQueue.shared.enqueue(WriteQueue.notes(note.entry.id), { try store.upsert(note.annotation, in: note.entry) }) { [weak self] error in
            app.show("Could not write to the notes file: \(error.localizedDescription)", isError: true)
            self?.reload(app: app)
        }
    }

    private struct Gone: Error {}

    // MARK: Markdown out

    /// The notes on screen as one Markdown document, grouped by book in reading order
    /// whatever the order on screen.
    func markdown(_ visible: [LibraryNote]) -> String {
        var order: [String] = [], byBook: [String: [LibraryNote]] = [:]
        for note in visible {
            if byBook[note.entry.id] == nil { order.append(note.entry.id) }
            byBook[note.entry.id, default: []].append(note)
        }
        let sections = order.compactMap { id -> String? in
            guard let group = byBook[id], let entry = group.first?.entry else { return nil }
            return CoreaderCommand.exportSection(entry, NotesDocument.readingOrder(group.map(\.annotation)))
        }
        let header = "# Reading notes\n\n\(visible.count) \(visible.count == 1 ? "note" : "notes") from \(sections.count) \(sections.count == 1 ? "book" : "books"). Blockquotes are passages from the books; the text under them is the reader's own. Each link opens the passage in Coreader.\n"
        return header + "\n" + sections.joined(separator: "\n")
    }

    static func markdown(for note: LibraryNote) -> String {
        let a = note.annotation
        var parts: [String] = []
        if !a.quote.isEmpty { parts.append(a.quote.split(separator: "\n").map { "> \($0)" }.joined(separator: "\n")) }
        if !a.note.isEmpty { parts.append(a.note) }
        let link = DeepLink.annotation(bookID: note.entry.id, annotationID: a.id).url.absoluteString
        parts.append("— *\(note.entry.book.title)*, [\(NotesDocument.positionLabel(for: a.locator))](\(link))")
        return parts.joined(separator: "\n\n")
    }
}
