import Observation
import SwiftUI
import WebKit

struct EPUBPreviewView: View {
    let fileURL: URL
    let onSelectionChange: @MainActor (DocumentSelection?) -> Void
    let onReadingPositionChange: @MainActor (Int?, [Int]) -> Void
    let loader: any EPUBBookLoading

    @State private var book: EPUBBook?
    @State private var currentSectionIndex = 0
    @State private var loadError: String?
    @State private var loadState = EPUBReaderLoadState()

    init(
        fileURL: URL,
        onSelectionChange: @escaping @MainActor (DocumentSelection?) -> Void,
        onReadingPositionChange: @escaping @MainActor (Int?, [Int]) -> Void,
        loader: any EPUBBookLoading = LiveEPUBBookLoader()
    ) {
        self.fileURL = fileURL
        self.onSelectionChange = onSelectionChange
        self.onReadingPositionChange = onReadingPositionChange
        self.loader = loader
    }

    var body: some View {
        Group {
            if let book {
                loadedState(for: book)
            } else if let loadError {
                ContentUnavailableView(
                    "Unable to open EPUB",
                    systemImage: "books.vertical",
                    description: Text(loadError)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("Opening EPUB")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: fileURL) {
            await loadBook()
        }
        .onChange(of: currentSectionIndex) { _, newValue in
            guard let book, book.sections.indices.contains(newValue) else {
                return
            }

            onSelectionChange(nil)
            onReadingPositionChange(newValue, [newValue])
        }
    }

    private func loadedState(for book: EPUBBook) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button("Previous", systemImage: "chevron.left") {
                    currentSectionIndex = max(0, currentSectionIndex - 1)
                }
                .buttonStyle(.bordered)
                .disabled(currentSectionIndex == 0)

                Picker("Chapter", selection: $currentSectionIndex) {
                    ForEach(Array(book.sections.enumerated()), id: \.element.id) { index, section in
                        Text(section.title).tag(index)
                    }
                }
                .labelsHidden()

                Button("Next", systemImage: "chevron.right") {
                    currentSectionIndex = min(book.sections.count - 1, currentSectionIndex + 1)
                }
                .buttonStyle(.bordered)
                .disabled(currentSectionIndex >= book.sections.count - 1)
            }

            HStack {
                Text(book.sections[currentSectionIndex].title)
                    .font(.headline)
                    .foregroundStyle(ReaderTheme.ink)

                Spacer()

                Text("Chapter \(currentSectionIndex + 1) of \(book.sections.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ReaderTheme.brass)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(ReaderTheme.canvas.opacity(0.9), in: Capsule())
            }

            EPUBSectionWebView(
                sectionURL: book.sections[currentSectionIndex].contentURL,
                readAccessURL: book.rootURL,
                onNavigateToSectionURL: { navigatedURL in
                    guard let sectionIndex = book.sectionIndex(for: navigatedURL),
                          sectionIndex != currentSectionIndex else {
                        return
                    }

                    currentSectionIndex = sectionIndex
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @MainActor
    private func loadBook() async {
        book = nil
        loadError = nil
        currentSectionIndex = 0
        onSelectionChange(nil)
        onReadingPositionChange(nil, [])
        let fileURL = fileURL.standardizedFileURL
        let requestID = loadState.startLoading(fileURL: fileURL)

        do {
            let loader = loader
            let loadedBook = try await Task.detached(priority: .userInitiated) {
                try loader.loadBook(from: fileURL)
            }.value

            guard loadState.accepts(requestID: requestID, fileURL: fileURL) else {
                return
            }
            book = loadedBook
            currentSectionIndex = 0
            onReadingPositionChange(0, [0])
        } catch {
            guard loadState.accepts(requestID: requestID, fileURL: fileURL.standardizedFileURL) else {
                return
            }
            loadError = error.localizedDescription
        }
    }
}

private struct EPUBSectionWebView: NSViewRepresentable {
    let sectionURL: URL
    let readAccessURL: URL
    let onNavigateToSectionURL: @MainActor (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigateToSectionURL: onNavigateToSectionURL)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true
        webView.navigationDelegate = context.coordinator
        context.coordinator.updateIfNeeded(webView: webView, sectionURL: sectionURL, readAccessURL: readAccessURL)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.updateIfNeeded(webView: nsView, sectionURL: sectionURL, readAccessURL: readAccessURL)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private var loadedSectionURL: URL?
        private let onNavigateToSectionURL: @MainActor (URL) -> Void

        init(onNavigateToSectionURL: @escaping @MainActor (URL) -> Void) {
            self.onNavigateToSectionURL = onNavigateToSectionURL
        }

        func updateIfNeeded(webView: WKWebView, sectionURL: URL, readAccessURL: URL) {
            let normalizedURL = sectionURL.standardizedFileURL
            guard loadedSectionURL != normalizedURL else {
                return
            }

            loadedSectionURL = normalizedURL
            webView.loadFileURL(normalizedURL, allowingReadAccessTo: readAccessURL)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            guard let currentURL = webView.url?.standardizedFileURL else {
                return
            }

            loadedSectionURL = currentURL
            Task { @MainActor in
                onNavigateToSectionURL(currentURL)
            }
        }
    }
}
