import CoreaderKit
import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var shelf = ShelfModel()
    @State private var isDropTarget = false
    @FocusState private var searchFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 148, maximum: 190), spacing: 34, alignment: .top)]

    var body: some View {
        @Bindable var shelf = shelf
        let visible = shelf.visible(app.books)
        VStack(spacing: 0) {
            header
            if app.books.isEmpty && app.isLoaded {
                EmptyShelf(isDropTarget: isDropTarget)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if shelf.tab == .library, !shelf.hasFilters {
                            Today(shelf: shelf)
                                .padding(.bottom, 40)
                        }
                        filters(count: visible.count)
                            .padding(.bottom, 24)
                        if visible.isEmpty {
                            NoMatches(shelf: shelf)
                        } else {
                            LazyVGrid(columns: columns, alignment: .leading, spacing: 40) {
                                ForEach(visible) { entry in
                                    BookCell(entry: entry, shelf: shelf)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 56)
                    .padding(.top, 28)
                    .padding(.bottom, 64)
                    .frame(maxWidth: 1500, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(palette.surface)
        .overlay {
            if isDropTarget && !app.books.isEmpty {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(palette.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .background(palette.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(14)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            Task {
                var urls: [URL] = []
                for provider in providers {
                    if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                       let file = URL(dataRepresentation: url, relativeTo: nil) { urls.append(file) }
                }
                app.importer.importFiles(urls)
            }
            return true
        }
        .sheet(item: $shelf.detail) { entry in
            BookDetail(entryID: entry.id)
                .environment(app)
                .environment(\.palette, palette)
        }
    }

    // MARK: Header

    private var header: some View {
        @Bindable var shelf = shelf
        return ZStack {
            // Centred on the window by themselves, so the search field growing does not
            // push them sideways.
            HStack(spacing: 26) {
                ForEach(ShelfTab.allCases) { tab in
                    let count = tab.status.map { s in app.books.filter { $0.book.status == s }.count } ?? app.books.count
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) { shelf.tab = tab }
                    } label: {
                        HStack(spacing: 5) {
                            Text(tab.title)
                                .font(Typo.ui(13, weight: shelf.tab == tab ? .semibold : .regular))
                                .foregroundStyle(shelf.tab == tab ? palette.ink : palette.secondary)
                            if count > 0 {
                                Text("\(count)")
                                    .font(Typo.ui(11).monospacedDigit())
                                    .foregroundStyle(palette.tertiary)
                            }
                        }
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(shelf.tab == tab ? palette.accent : .clear)
                                .frame(height: 1.5)
                                .offset(y: 4)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(shelf.tab == tab ? .isSelected : [])
                }
            }

            HStack(spacing: 0) {
            Text("Coreader")
                .font(.system(size: 19, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(palette.ink)
                .padding(.leading, 84)

            Spacer(minLength: 24)

            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.tertiary)
                    TextField("Search", text: $shelf.query)
                        .textFieldStyle(.plain)
                        .font(Typo.ui(13))
                        .foregroundStyle(palette.ink)
                        .focused($searchFocused)
                        .frame(width: searchFocused || !shelf.query.isEmpty ? 170 : 90)
                        .animation(.easeOut(duration: 0.18), value: searchFocused)
                    if !shelf.query.isEmpty {
                        Button { shelf.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(palette.tertiary) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(palette.raised.opacity(0.8), in: Capsule())
                .overlay(Capsule().strokeBorder(palette.rule, lineWidth: 0.5))
                .padding(.trailing, 6)

                ChromeButton(symbol: "rectangle.stack", help: "Daily review", badge: app.review.due.count) { app.overlay = .review }
                ChromeButton(symbol: "point.3.connected.trianglepath.dotted", help: "Notes graph") { app.overlay = .graph }
                ChromeButton(symbol: "gearshape", help: "Settings") { app.overlay = .settings }

                Menu {
                    Button("Add Files…") { app.importer.chooseFiles() }
                    Button("Add from Link…") { app.overlay = .addLink }
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(Typo.ui(13, weight: .medium))
                        .foregroundStyle(palette.page)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(palette.ink, in: Capsule())
                } primaryAction: {
                    app.importer.chooseFiles()
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .padding(.leading, 6)
                .help("Add books (click) or add from a link (hold)")
            }
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

    // MARK: Filters

    private func filters(count: Int) -> some View {
        @Bindable var shelf = shelf
        return HStack(spacing: 10) {
            Text(shelf.tab == .library ? "All books" : shelf.tab.title)
                .font(Typo.display(22))
                .foregroundStyle(palette.ink)
            Text("\(count)")
                .font(Typo.ui(13).monospacedDigit())
                .foregroundStyle(palette.tertiary)
                .padding(.top, 5)

            Spacer()

            HStack(spacing: 4) {
                FilterChip(title: "All", isOn: shelf.kind == nil) { shelf.kind = nil }
                FilterChip(title: "Books", isOn: shelf.kind == .book) { shelf.kind = .book }
                FilterChip(title: "Papers", isOn: shelf.kind == .paper) { shelf.kind = .paper }
                FilterChip(title: "Articles", isOn: shelf.kind == .article) { shelf.kind = .article }
            }

            Rectangle().fill(palette.rule).frame(width: 0.5, height: 16).padding(.horizontal, 4)

            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { n in
                    Button {
                        shelf.stars = shelf.stars == n ? nil : n
                    } label: {
                        HStack(spacing: 2) {
                            Text("\(n)").font(Typo.ui(12, weight: .medium).monospacedDigit())
                            Image(systemName: "star.fill").font(.system(size: 9))
                        }
                        .foregroundStyle(shelf.stars == n ? Color(hex: 0xB07A16) : palette.secondary)
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                        .background(shelf.stars == n ? Color(hex: 0xD99A2B).opacity(0.18) : .clear, in: Capsule())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Show \(n)-star books")
                    .accessibilityLabel("\(n) stars")
                    .accessibilityAddTraits(shelf.stars == n ? .isSelected : [])
                }
            }

            Rectangle().fill(palette.rule).frame(width: 0.5, height: 16).padding(.horizontal, 4)

            Menu {
                Picker("Sort by", selection: $shelf.sort) {
                    ForEach(ShelfSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 10, weight: .medium))
                    Text(shelf.sort.title).font(Typo.ui(12))
                }
                .foregroundStyle(palette.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

// MARK: - Pieces

struct ChromeButton: View {
    let symbol: String
    let help: String
    var badge = 0
    var isOn = false
    let action: () -> Void
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(isOn ? palette.accent : (hovering ? palette.ink : palette.secondary))
                .frame(width: 30, height: 30)
                .background(isOn ? palette.accent.opacity(0.12) : (hovering ? palette.ink.opacity(0.06) : .clear),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 9, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(palette.accent, in: Capsule())
                            .offset(x: 3, y: -2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(badge > 0 ? "\(help), \(badge)" : help)
    }
}

struct FilterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Typo.ui(12, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? palette.ink : palette.secondary)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(isOn ? palette.ink.opacity(0.08) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// One book on the shelf.
private struct BookCell: View {
    let entry: BookEntry
    let shelf: ShelfModel
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette
    @State private var hovering = false

    var body: some View {
        let book = entry.book
        VStack(alignment: .leading, spacing: 0) {
            Button { app.open(entry.id) } label: {
                BookCover(entry: entry, width: 150)
                    .overlay(alignment: .topTrailing) {
                        if book.status == .read {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Color(hex: 0x4E7A52), in: Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1))
                                .offset(x: 6, y: -6)
                                .accessibilityLabel("Read")
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if book.status == .reading, book.progress > 0.005 {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(.black.opacity(0.35))
                                    Rectangle().fill(.white.opacity(0.95)).frame(width: geo.size.width * book.progress)
                                }
                            }
                            .frame(height: 3)
                            .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                        }
                    }
                    .offset(y: hovering ? -4 : 0)
                    .animation(.spring(duration: 0.3), value: hovering)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 14)

            Button { shelf.detail = entry } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(Typo.display(13.5, weight: .medium))
                        .foregroundStyle(palette.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !book.authorLine.isEmpty {
                        Text(book.shortAuthors)
                            .font(Typo.ui(11.5))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Details")

            HStack(spacing: 6) {
                if let status = app.busyBooks[entry.id] {
                    ProgressView().controlSize(.mini)
                    Text(status).font(Typo.ui(10.5)).foregroundStyle(palette.tertiary).lineLimit(1)
                } else {
                    // Always there, so rating a book never depends on finding a hover state.
                    StarRating(rating: book.rating, size: 10) { app.setRating($0, for: entry.id) }
                        .opacity(book.rating == nil && !hovering ? 0.55 : 1)
                }
                Spacer(minLength: 0)
                Text(book.format == .article ? "WEB" : book.format.rawValue.uppercased())
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(palette.tertiary)
                Menu {
                    BookMenu(entry: entry, shelf: shelf)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                        .frame(width: 18, height: 16)
                        .contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help("Shelf, rating and more")
                .accessibilityLabel("Actions for \(book.title)")
            }
            .frame(height: 16)
            .padding(.top, 6)
        }
        .frame(width: 150, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { BookMenu(entry: entry, shelf: shelf) }
    }
}

struct BookMenu: View {
    let entry: BookEntry
    var shelf: ShelfModel?
    @Environment(AppModel.self) private var app

    var body: some View {
        Button("Open") { app.open(entry.id) }
        if let shelf { Button("Details…") { shelf.detail = entry } }
        Divider()
        Picker("Shelf", selection: Binding(get: { entry.book.status }, set: { app.setStatus($0, for: entry.id) })) {
            ForEach(ReadingStatus.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        Picker("Rating", selection: Binding(get: { entry.book.rating ?? 0 }, set: { app.setRating($0 == 0 ? nil : $0, for: entry.id) })) {
            Text("None").tag(0)
            ForEach(1...5, id: \.self) { Text(String(repeating: "★", count: $0)).tag($0) }
        }
        Picker("Kind", selection: Binding(get: { entry.book.kind }, set: { kind in app.update(entry.id) { $0.kind = kind } })) {
            Text("Book").tag(BookKind.book)
            Text("Paper").tag(BookKind.paper)
            Text("Article").tag(BookKind.article)
        }
        Divider()
        Button("Design a New Cover") { Task { await app.importer.generateCover(for: entry.id) } }
        Button("Show Notes in Finder") { app.revealInFinder(entry.id) }
        Divider()
        Button("Remove from Library…", role: .destructive) { app.confirmDelete = entry }
    }
}

/// Top of the library: what to pick up next, and today's reading at a glance.
private struct Today: View {
    let shelf: ShelfModel
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    private var current: [BookEntry] {
        app.books.filter { $0.book.status == .reading }
            .sorted { ($0.book.lastOpenedAt ?? .distantPast) > ($1.book.lastOpenedAt ?? .distantPast) }
    }

    var body: some View {
        if let lead = current.first {
            HStack(alignment: .top, spacing: 40) {
                Button { app.open(lead.id) } label: { BookCover(entry: lead, width: 176) }
                    .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Continue reading").labelStyle(palette)
                    Text(lead.book.title)
                        .font(Typo.display(34, weight: .regular))
                        .foregroundStyle(palette.ink)
                        .lineLimit(2)
                        .padding(.top, 10)
                    if !lead.book.authorLine.isEmpty {
                        Text(lead.book.shortAuthors)
                            .font(Typo.serif(16, italic: true))
                            .foregroundStyle(palette.secondary)
                            .padding(.top, 4)
                    }

                    HStack(spacing: 12) {
                        ProgressLine(value: lead.book.progress).frame(width: 220)
                        Text(progressText(lead.book))
                            .font(Typo.ui(12).monospacedDigit())
                            .foregroundStyle(palette.secondary)
                    }
                    .padding(.top, 22)

                    HStack(spacing: 10) {
                        Button { app.open(lead.id) } label: {
                            Text("Resume")
                                .font(Typo.ui(13, weight: .semibold))
                                .foregroundStyle(palette.page)
                                .padding(.horizontal, 20)
                                .frame(height: 34)
                                .background(palette.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.defaultAction)

                        if current.count > 1 {
                            HStack(spacing: -18) {
                                ForEach(current.dropFirst().prefix(4)) { other in
                                    Button { app.open(other.id) } label: { BookCover(entry: other, width: 30) }
                                        .buttonStyle(.plain)
                                        .help(other.book.title)
                                        .padding(.leading, 24)
                                }
                            }
                        }
                    }
                    .padding(.top, 22)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                TodayStats()
                    .frame(width: 250)
            }
            .frame(height: 264)
        } else {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nothing on the go").labelStyle(palette)
                    Text("Pick a book to start.")
                        .font(Typo.display(30, weight: .regular))
                        .foregroundStyle(palette.ink)
                }
                Spacer()
                TodayStats().frame(width: 250)
            }
        }
    }

    private func progressText(_ book: Book) -> String {
        let percent = "\(book.progress.percent)%"
        guard book.secondsRead > 300, book.progress > 0.03, book.progress < 0.99 else { return percent }
        let remaining = book.secondsRead / book.progress * (1 - book.progress)
        return "\(percent)  ·  about \(Duration.seconds(remaining).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 1))) left"
    }
}

/// Today's reading: minutes, streak, the week, and the review waiting.
private struct TodayStats: View {
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        let review = app.review
        VStack(alignment: .leading, spacing: 0) {
            Text("Today").labelStyle(palette)
            HStack(alignment: .firstTextBaseline, spacing: 22) {
                stat("\(review.secondsToday.minutes)", "min read")
                stat("\(review.streak)", review.streak == 1 ? "day streak" : "day streak")
                stat("\(review.all.filter { $0.annotation.kind != .image }.count)", "notes")
            }
            .padding(.top, 12)

            HStack(alignment: .bottom, spacing: 5) {
                let peak = max(review.week.map(\.seconds).max() ?? 0, 20 * 60)
                ForEach(Array(review.week.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(day.seconds >= 300 ? palette.accent.opacity(0.85) : palette.rule)
                            .frame(height: max(3, 34 * day.seconds / peak))
                        Text(day.day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(palette.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52, alignment: .bottom)
                    .help("\(day.seconds.minutes) min")
                }
            }
            .padding(.top, 18)

            Spacer(minLength: 12)

            Button { app.overlay = .review } label: {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.stack").font(.system(size: 12))
                    Text(review.due.isEmpty ? "Review is clear for today" : "\(review.due.count) highlight\(review.due.count == 1 ? "" : "s") to review")
                        .font(Typo.ui(12.5, weight: .medium))
                    Spacer()
                    if !review.due.isEmpty { Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold)) }
                }
                .foregroundStyle(review.due.isEmpty ? palette.tertiary : palette.ink)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(palette.raised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(palette.rule, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(review.due.isEmpty)
        }
        .padding(.leading, 28)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .leading) { Rectangle().fill(palette.rule).frame(width: 0.5) }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(Typo.display(26, weight: .regular).monospacedDigit()).foregroundStyle(palette.ink)
            Text(label).font(Typo.ui(11)).foregroundStyle(palette.secondary)
        }
    }
}

struct ProgressLine: View {
    let value: Double
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.rule)
                Capsule().fill(palette.ink.opacity(0.75)).frame(width: max(3, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 3)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(value.percent) percent")
    }
}

private struct EmptyShelf: View {
    let isDropTarget: Bool
    @Environment(AppModel.self) private var app
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            HStack(spacing: -34) {
                ForEach(Array(["The Art of\nDoing Science", "Notes on\nReading", "Attention Is\nAll You Need"].enumerated()), id: \.offset) { i, title in
                    PlaceholderCover(book: Book(title: title, authors: [], format: .epub, fileName: ""))
                        .frame(width: 104, height: 156)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
                        .rotationEffect(.degrees(Double(i - 1) * 7))
                        .offset(y: i == 1 ? -10 : 4)
                        .zIndex(i == 1 ? 1 : 0)
                }
            }
            .padding(.bottom, 36)
            Text("Your shelf is empty")
                .font(Typo.display(30, weight: .regular))
                .foregroundStyle(palette.ink)
            Text("Drop EPUB, PDF, MOBI or AZW3 files here,\nor paste a link to a paper or an article.")
                .font(Typo.ui(14))
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 8)
            HStack(spacing: 10) {
                Button { app.importer.chooseFiles() } label: {
                    Text("Add Books…")
                        .font(Typo.ui(13, weight: .semibold))
                        .foregroundStyle(palette.page)
                        .padding(.horizontal, 20).frame(height: 36)
                        .background(palette.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                Button { app.overlay = .addLink } label: {
                    Text("Add from Link…")
                        .font(Typo.ui(13, weight: .medium))
                        .foregroundStyle(palette.ink)
                        .padding(.horizontal, 20).frame(height: 36)
                        .overlay(Capsule().strokeBorder(palette.rule, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 26)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(palette.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .padding(18)
            }
        }
    }
}

private struct NoMatches: View {
    let shelf: ShelfModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 10) {
            Text(shelf.hasFilters ? "Nothing matches these filters" : "Nothing on this shelf yet")
                .font(Typo.display(20, weight: .regular))
                .foregroundStyle(palette.ink)
            if shelf.hasFilters {
                Button("Clear filters") { shelf.clearFilters() }
                    .buttonStyle(.plain)
                    .font(Typo.ui(13, weight: .medium))
                    .foregroundStyle(palette.accent)
            } else {
                Text("Books move here as you mark them.")
                    .font(Typo.ui(13))
                    .foregroundStyle(palette.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}
