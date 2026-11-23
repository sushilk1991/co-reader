import CoreaderKit
import SwiftUI

/// Everything about one book: shelf, rating, summary, and what you took from it.
struct BookDetail: View {
    let entryID: String
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var notes: [Annotation] = []
    @State private var title = ""
    @State private var authors = ""
    @State private var editing = false

    var body: some View {
        if let entry = app.entry(entryID) {
            let book = entry.book
            HStack(alignment: .top, spacing: 36) {
                VStack(spacing: 16) {
                    BookCover(entry: entry, width: 210, grows: true)
                    if let status = app.busyBooks[entry.id] {
                        HStack(spacing: 6) { ProgressView().controlSize(.mini); Text(status).font(Typo.ui(11)).foregroundStyle(palette.tertiary) }
                    } else {
                        Button("Design a new cover") { Task { await app.importer.redesignCover(for: entry.id) } }
                            .buttonStyle(.plain).font(Typo.ui(11.5)).foregroundStyle(palette.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(book.kind == .book ? book.format.rawValue.uppercased() : (book.kind == .paper ? "Paper" : "Article")).labelStyle(palette)
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.tertiary)
                                .frame(width: 26, height: 26).background(palette.ink.opacity(0.06), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Close")
                    }

                    if editing {
                        TextField("Title", text: $title).textFieldStyle(.roundedBorder).font(Typo.display(18)).padding(.top, 10)
                        TextField("Authors, separated by commas", text: $authors).textFieldStyle(.roundedBorder).padding(.top, 6)
                        Button("Done") {
                            let t = title.trimmingCharacters(in: .whitespaces)
                            let a = authors.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                            app.update(entry.id) { if !t.isEmpty { $0.title = t }; $0.authors = a }
                            editing = false
                        }
                        .padding(.top, 8)
                    } else {
                        Text(book.title)
                            .font(Typo.display(28, weight: .regular))
                            .foregroundStyle(palette.ink)
                            .lineLimit(3)
                            .padding(.top, 10)
                            .textSelection(.enabled)
                        HStack(spacing: 8) {
                            if !book.authorLine.isEmpty {
                                Text(book.authorLine).font(Typo.serif(15, italic: true)).foregroundStyle(palette.secondary).lineLimit(2)
                            }
                            Button {
                                title = book.title
                                authors = book.authors.joined(separator: ", ")
                                editing = true
                            } label: { Image(systemName: "pencil").font(.system(size: 11)).foregroundStyle(palette.tertiary) }
                                .buttonStyle(.plain)
                                .help("Edit title and authors")
                                .accessibilityLabel("Edit title and authors")
                        }
                        .padding(.top, 4)
                    }

                    HStack(spacing: 18) {
                        Picker("Shelf", selection: Binding(get: { book.status }, set: { app.setStatus($0, for: entry.id) })) {
                            ForEach(ReadingStatus.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 250)
                        StarRating(rating: book.rating, size: 17) { app.setRating($0, for: entry.id) }
                    }
                    .padding(.top, 20)

                    HStack(spacing: 22) {
                        fact("\(book.progress.percent)%", "read")
                        fact(Duration.seconds(book.secondsRead).formatted(.units(allowed: [.hours, .minutes], width: .narrow, maximumUnitCount: 2)), "time")
                        fact("\(notes.filter { $0.kind == .highlight }.count)", "highlights")
                        fact("\(notes.filter { !$0.note.isEmpty }.count)", "notes")
                        if let pages = book.pageCount { fact("\(pages)", "pages") }
                        if let year = book.year { fact(String(year), "year") }
                    }
                    .padding(.top, 22)

                    if let summary = book.summary, !summary.isEmpty {
                        ScrollView {
                            Text(summary)
                                .font(Typo.serif(14))
                                .lineSpacing(4)
                                .foregroundStyle(palette.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 150)
                        .padding(.top, 20)
                    }

                    Spacer(minLength: 20)

                    HStack(spacing: 10) {
                        Button {
                            dismiss()
                            app.open(entry.id)
                        } label: {
                            Text(book.progress > 0.01 ? "Continue reading" : "Start reading")
                                .font(Typo.ui(13, weight: .semibold))
                                .foregroundStyle(palette.page)
                                .padding(.horizontal, 20).frame(height: 34)
                                .background(palette.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.defaultAction)

                        Menu("More") {
                            Button("Turn This Book into a Skill…") { dismiss(); app.makeSkill(from: entry.id) }
                            Button("Show Notes in Finder") { app.revealInFinder(entry.id) }
                            if let source = book.sourceURL.flatMap(URL.init(string:)) {
                                Button("Open Source Page") { NSWorkspace.shared.open(source) }
                            }
                            Divider()
                            Button("Remove from Library…", role: .destructive) { dismiss(); app.confirmDelete = entry }
                        }
                        .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(34)
            .frame(width: 780, height: 460)
            .background(palette.page)
            .task {
                let store = app.notes
                notes = (try? await offMain { try store.load(entry) }) ?? []
            }
        }
    }

    private func fact(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(Typo.display(18, weight: .regular).monospacedDigit()).foregroundStyle(palette.ink)
            Text(label).font(Typo.ui(10.5)).foregroundStyle(palette.tertiary)
        }
    }
}

/// Paste a link to a paper (arXiv, DOI) or any article.
struct AddLinkView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Add from a link").font(Typo.display(20)).foregroundStyle(palette.ink)
            Text("An arXiv link or id, a DOI, or any article on the web.")
                .font(Typo.ui(12.5)).foregroundStyle(palette.secondary).padding(.top, 4)
            TextField("https://arxiv.org/abs/1706.03762", text: $link)
                .textFieldStyle(.plain)
                .font(Typo.ui(14))
                .padding(.horizontal, 12).frame(height: 38)
                .background(palette.raised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.rule, lineWidth: 1))
                .focused($focused)
                .onSubmit(add)
                .padding(.top, 18)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add", action: add).keyboardShortcut(.defaultAction)
                    .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 20)
        }
        .padding(26)
        .frame(width: 480)
        .background(palette.page)
        .onAppear {
            focused = true
            // A link already on the clipboard is almost always the one meant.
            if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
               clip.count < 300, clip.hasPrefix("http") || clip.range(of: #"^\d{4}\.\d{4,5}"#, options: .regularExpression) != nil || clip.hasPrefix("10.") {
                link = clip
            }
        }
    }

    private func add() {
        let text = link.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        app.importer.importLink(text)
        dismiss()
    }
}
