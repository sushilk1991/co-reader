# Product intent

Last audited from source: 2026-09-15 (v0.2.1, marketing version in `project.yml`).

CoReader is a local macOS reader for PDFs and EPUBs: highlight passages, take
notes, and ask questions against the open document. Captain direction: a reader
where those three jobs work, and the app stops crashing and feeling unpolished.

Who it is for is not confirmed. Code and copy assume a single person studying
dense documents on a Mac, with Ollama or Claude CLI already installed. That
audience is an open question, not a market claim.

## Confirmed direction

From the captain:

- Notes, highlights, and talking to a PDF are the product.
- The current app crashes and has many things that do not work.
- It is not polished; that is in-scope to name and later fix.

From v0.2.0 user-testing commit `6c3f0b6` (already in the tree): LM Studio /
OpenAI-compatible was removed; the user uses Ollama and Claude CLI only.

## What the code actually is

A SwiftUI macOS 15 app (`com.sushil.CoReaderApp`) shipped as an unsigned DMG.
There is no iOS target, no sandbox entitlements file, no account system, and no
hosted backend.

The window is a reader workspace (`ReaderWorkspaceView`) with a collapsible
library, a PDFKit or EPUB/WebKit preview, and a collapsible inspector:

| Job | What ships today |
| --- | --- |
| Read | PDF via `PDFPreviewView`; EPUB via `EPUBPreviewView` (unzip with `/usr/bin/ditto`, render HTML in `WKWebView`) |
| Highlight | PDF: toolbar pen writes `PDFAnnotation` highlights persisted under iCloud-or-local `Highlights/`. EPUB: note records only, no in-book mark |
| Notes | Markdown files + a local SQLite index (`KnowledgeRepository`) |
| Talk to the document | `DocumentAssistant` over local Ollama (`127.0.0.1:11434`) or `claude -p`; scopes are selection, current page/chapter, or a document sweep |
| Diagrams | On PDF select, `PDFVisualExtractor` scans image XObjects and crops page renders into the Visuals tab |
| Resume | `ReadingState.json` stores file paths and page indexes |

Library, inspector, and command palette (`⌘K`) start closed. Chat, notes, and
highlights are behind **Show Tools**.

## Out of scope until the captain says otherwise

Grounded in what is absent from the targets and in `6c3f0b6`:

- iOS, iPad, or a multiplatform target
- Hosted LLM APIs, accounts, billing, telemetry
- Cloud OCR / scanned-PDF text recovery (`LiveDocumentContextExtractor` already
  reports when a PDF has no extractable text)
- In-book EPUB highlight rendering
- Copying imports into an app-owned library (the library stores original URLs)

`docs/plans/` is historical implementation notes, not current product law.

## Current state (not polished)

Unit tests pass (`swift test`: 58 Swift Testing tests on 2026-09-15). That does
not mean the GUI is stable. Findings below are from reading this tree and
running those tests, not from a crash log. They are scheduled as later work;
this document does not fix them.

### Crashes and freezes

1. `AppModel.swift:675` — selecting a PDF runs `extractVisuals` synchronously
   on `@MainActor`. Trigger: import/select a PDF. Effect: UI freeze while every
   page is scanned and rendered (up to 1600px); Force Quit looks like a crash.
2. `PDFImagePlacementScanner.swift:130-147` — `Do` on a Form XObject recurses
   into `scanPDFContentStream` with no depth cap or visited set. Trigger: a PDF
   whose forms nest deeply or cycle. Effect: stack overflow abort.
3. `ProcessCommandRunner.swift:14-15` — `waitUntilExit()` with no timeout, on
   the MainActor via `AppModel.refreshProviders` / `ClaudeCodeClient`. Trigger:
   launch (Claude probe falls through to `/bin/zsh -l -c "claude --version"` at
   `ClaudeCLIProbe.swift:35-38`) or Ask when Claude is the fallback. Effect:
   beach-ball; a hanging login shell never returns.
4. `HighlightingPDFView.swift:115-146` via `PDFPreviewView.swift:36` — every
   SwiftUI `updateNSView` strips and re-adds all highlight annotations. Trigger:
   scrolling (page-change mutates `AppModel`, so the representable updates).
   Effect: PDFKit mutation during layout, flicker, hang.
5. `EPUBPreviewView.swift:199-217` — `WKUserContentController.add` has no
   matching `removeScriptMessageHandler` in `deinit`. Trigger: close or switch
   an EPUB. Effect: WebKit teardown crash.
6. `LiveDocumentContextExtractor.swift:52-63` — Ask walks `page.string` for
   every PDF page on the MainActor before the LLM `await`. Trigger: question on
   a long PDF. Effect: UI freeze.
7. `DocumentPreviewPanel.swift:175-177` — page-count load calls
   `LiveEPUBBookLoader.loadBook` on `.task` (MainActor), and
   `LiveEPUBBookLoader.swift:73-74` blocks on `ditto`. Trigger: open an EPUB.
   Effect: freeze; duplicate work with `EPUBPreviewView`.

### Features that do not actually work

8. `AppModel.swift:671` restores a page index, but `PDFPreviewView.swift:88`
   never `go(to:)` and `EPUBPreviewView.swift:137` resets to chapter 0.
   `PDFPreviewView.swift:142-148` then publishes page 0 through
   `updateReadingPosition`, which overwrites the saved position. Trigger:
   quit mid-document, relaunch. Effect: always starts at the beginning.
9. `ProviderStatusView.swift:12-21` — `fileImporter` never calls
   `startAccessingSecurityScopedResource()`. Trigger: Import PDF or EPUB.
   Effect: open/extract can fail once the importer callback ends.
10. `DocumentLibrary.swift:6-15` stores the original URL only.
    `AppModel.swift:532-534` skips missing paths with no message. Trigger:
    move/delete the file, or relaunch. Effect: library silently shrinks.
11. `OllamaClient.swift:41-43` sorts model names;
    `DocumentAssistant.swift:87-88` uses `models[0]`. Trigger: Ask while
    Ollama lists an embed model before a chat model. Effect: generation fails
    or returns garbage (“talk to PDF does not work”).
12. `ClaudeCodeClient.swift:11-20` puts the whole prompt on `claude -p` argv.
    Trigger: a long excerpt. Effect: argument-list too long, or a truncated
    question.
13. `CoReaderPaths.swift:41-50` treats
    `Library/Mobile Documents/com~apple~CloudDocs` as iCloud;
    `ReadingStateStore.swift:17` reads with `Data(contentsOf:)` and no
    `NSFileCoordinator`. Notes markdown is synced (`LiveKnowledgeRepository.swift:8`);
    the SQLite index is local-only (`…:9-16`) with no rebuild-from-markdown.
    Trigger: second Mac, or a dataless placeholder. Effect: hang on launch, or
    notes that exist as files but do not search.
14. `AppModel.swift:679-680` scopes notes by `lastPathComponent`, not full
    path. Trigger: two files named the same. Effect: mixed notes.
15. `AppModel.swift:615-617` swallows auto-summary errors. Trigger: no model
    or a failed generate. Effect: the summary card never appears and does not
    say why.

Polish that matches “unpolished”: window min size 1120×760
(`CoReaderApp.swift:10`); inspector and library closed at launch; EPUB
highlights are list rows only (`SelectionActionBar.swift:46-54`); highlight
annotation colors are fixed calibrated RGB (`ReaderHighlightColor.swift:23-34`),
not appearance-adaptive.

## Open questions for the captain

1. Who is the first user — the captain only, students, or researchers?
2. Keep AI local-only (Ollama + Claude CLI), or bring back a localhost
   OpenAI-compatible adapter?
3. Is iCloud Drive a real requirement, or should notes and reading state stay
   in Application Support?
4. Is EPUB a first-class peer to PDF (in-book highlights, restored chapter), or
   PDF-first with EPUB as preview?
5. Should import copy files into an app-owned library so the original can move?
