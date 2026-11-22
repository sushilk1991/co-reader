# Coreader

A reading app for Mac (iOS and iPad next): EPUB, PDF, MOBI/AZW3 and saved web articles,
with highlights and notes kept as plain Markdown, and an AI side panel that drives the
agent CLIs already on the machine (Claude Code, Codex, Antigravity).

## Layout

| Path | What |
| --- | --- |
| `Sources/CoreaderKit` | Platform-neutral core (models, library, notes, agents, papers, covers, review, graph). Foundation plus CryptoKit, NaturalLanguage and PDFKit: no AppKit, UIKit or SwiftUI, so iOS can reuse it. |
| `Sources/coreader-cli` | `coreader` command for people and agents to query the library and notes. |
| `Sources/CoreaderApp` | The macOS SwiftUI app. |
| `Sources/CoreaderApp/Web` | The web reader (vendored foliate-js + `bridge.js`) shown in a `WKWebView` for every format except PDF. |
| `Tests/CoreaderKitTests` | Swift Testing unit tests for the core. |
| `integrations/` | Agent skill, Mastisk plugin, browser extension. |

## Commands

```bash
swift build && swift test          # core + CLI
xcodegen generate --spec project.yml
make build                         # the .app
make build-and-run-background      # launch without taking focus
scripts/dev_start.sh               # run off-screen and drive it: docs/driving-the-app.md
```

Rerun `xcodegen` after adding or removing files under `Sources/CoreaderApp`.

## The library on disk (the contract everything shares)

One folder, by default `iCloud Drive/Coreader` (falls back to `~/Documents/Coreader`
when iCloud Drive is off). The chosen root is recorded in
`~/Library/Application Support/Coreader/config.json` (`{"libraryRoot": "/abs/path"}`)
so the app and the CLI agree.

```
Coreader/
  README.md                 written by the app; explains this layout to agents
  Books/<slug>/
    book.json               metadata (Book): status, rating, progress, location...
    notes.md                every highlight, note and saved image for this book
    <slug>.<ext>            the book file itself
    cover.jpg|png           cover (from the file, or generated)
    assets/                 images saved or snipped from the book
    chats/                  saved AI conversations, Markdown
    skill/                  the book distilled into an agent skill, if built
  review.json               spaced-repetition state for the daily review
  reading-log.json          minutes read per day (streak, weekly chart)
```

Rules:

- **Markdown is the only copy of the notes.** There is no notes database. Anything
  derived (search index, embeddings, extracted book text) lives in
  `~/Library/Caches/Coreader/` and can be deleted at any time.
- Writes are atomic (write to a temp file, then replace) because iCloud and other
  tools (Mastisk, Obsidian, agents) read the same files.
- `book.json` uses ISO 8601 dates and pretty-printed, sorted keys so diffs and sync
  conflicts stay readable.
- Deep links (`coreader://open?book=<id>&a=<annotationID>`, `&page=<n>`, `&cfi=<cfi>`)
  are how notes, agents and the CLI point back into a book. See `DeepLink`.

## Guardrails

- Every write of `notes.md` or `book.json` goes through `WriteQueue` (ordered per book;
  quitting waits for it). Annotation edits are applied to the copy in the file
  (`NotesStore.update`), never by writing back a copy loaded earlier.
- Book content is untrusted: the web reader's CSP allows only bundled scripts, only the
  main frame may message the app, and links from books open only as http(s)/mailto.
- Agents get read-only access to the book and notes. The one job that writes
  (book-to-skill) works in a staging folder, never in the book's folder.

- Swift 6 language mode, strict concurrency. Nothing blocking on the main actor.
- Child processes always carry a timeout and are killed when their task is cancelled.
- Tests are Swift Testing (`import Testing`, `@Test`). No network and no real agent
  CLIs in unit tests: inject fakes.
- Comments explain non-obvious reasons and traps, not what the code says.
- Keep this file short; point at code instead of repeating it.
