# Product intent

Last audited from source: 2026-09-15 (v0.2.1, marketing version in `project.yml`),
re-audited the same day after the fourteen defects below were fixed.

CoReader is a local macOS reader for PDFs and EPUBs: highlight passages, take
notes, and ask questions against the open document. Confirmed direction: a
reader where those three jobs work, and the app stops crashing and feeling
unpolished.

Who it is for is not confirmed. Code and copy assume a single person studying
dense documents on a Mac, with Ollama or Claude CLI already installed. That
audience is an open question, not a market claim.

## User-Confirmed Direction

From Sushil:

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

## Out of scope until Sushil says otherwise

Grounded in what is absent from the targets and in `6c3f0b6`:

- iOS, iPad, or a multiplatform target
- Hosted LLM APIs, accounts, billing, telemetry
- Cloud OCR / scanned-PDF text recovery (`LiveDocumentContextExtractor` already
  reports when a PDF has no extractable text)
- In-book EPUB highlight rendering
- Copying imports into an app-owned library (the library stores original URLs)
- App Sandbox. If it is ever enabled, `ProviderStatusView`'s `fileImporter` callback must
  call `startAccessingSecurityScopedResource()` on `fileImporter` URLs, or
  open/extract fails once the importer callback ends.

`docs/plans/` is historical implementation notes, not current product law.

## Current state (not polished)

Unit tests pass (`swift test`, 2026-09-15). That does
not mean the GUI is stable. The fourteen findings below came from reading this
tree, not from a crash log. Each was fixed on 2026-09-15 with a failing test
first where a unit test could express the rule; the entries now describe what
the code does today and what is still open. Follow-ups found while fixing are
listed after item 14 and are not scheduled here.

### Crashes and freezes

1. `AppModel.startVisualExtraction` — selecting a PDF now runs `extractVisuals` through
   `BlockingWork.run` on a GCD thread, cancellable (Cancel button in the
   Visuals panel, or switching documents), with "Scanning N of M pages"
   progress in the panel while the user waits. What gets extracted is
   unchanged.
2. `PDFImagePlacementScanner.defaultMaxFormDepth`, `PDFFormNesting` — Form XObject recursion is bounded
   by `defaultMaxFormDepth` (12) and an ancestor set, so a form that draws
   itself or cycles is entered once per path. Deeper nesting is skipped, not
   scanned.
3. `ProcessCommandRunner` (`scheduleTimeout`, `expire`) — every `ShellCommand` carries a
   `timeout`; on expiry the process is terminated and `ShellCommandError.timedOut`
   is thrown. `ClaudeCLIProbe.probeTimeout` (15 s) turns that into
   `.unavailable(reason:)`, and `ClaudeCodeClient.generationTimeout` (300 s) into a
   generation failure. The reason reaches the status pill tooltip
   (`ReaderToolbarView.swift`, `AppModel.providerReadinessDetail`), so
   "Scanning AI" ends within the probe timeout.
4. `HighlightingPDFView.syncManagedHighlights` diffs managed
   annotations by highlight id and only adds, removes, or replaces the ones
   that changed; `PDFPreviewView.swift` skips the call when the highlight list
   is unchanged. Scrolling no longer mutates PDFKit annotations.
5. `EPUBPreviewView.Coordinator` (`configure`, `detach`, `dismantleNSView`) — the web view registers the
   coordinator directly as the script message handler, and `dismantleNSView`
   calls `detach`, which removes the handler and user scripts, so the
   coordinator and the `AppModel` closures it captured are released with the view.
6. `DocumentAssistant.answer`, `LiveDocumentContextExtractor.extractPDFPageTexts` —
   the PDF `page.string` walk runs through `BlockingWork.run`, checks
   cancellation per page, and reports `PageScanProgress`; the chat panel shows
   "N of M pages" with a Cancel button while an Ask is in flight.
7. `DocumentPreviewPanel` (`onPageCountChange`, `onSectionCountChange`) — the EPUB page count now comes from
   `EPUBPreviewView`'s own load via `onSectionCountChange`; the panel no
   longer calls `LiveEPUBBookLoader.loadBook` on the MainActor.

### Features that do not actually work

8. Reading position is restored. `PDFPreviewView.beginRestore` and `applyRestoreStep` drive
   `ReadingPositionRestoreState`: it calls `go(to:)`, re-applies when PDFKit
   reports an interim page 0, suppresses position publishing until a layout
   pass shows the target page, and gives up after four attempts or 1.5 s.
   `EPUBPreviewView` opens at `initialSectionIndex`.
   `AppModel.restoreReadingStateIfNeeded` loads state off the actor
   at launch; saves are suppressed while restoring and flushed on
   `willTerminate`.
9. `AppModel.missingLibraryFiles` — restore collects `missingLibraryFiles` and shows a
   dismissable banner naming each file that could not be found. The library
   still stores original URLs (see Out of scope).
10. `OllamaModelTag.supportsChat`, `OllamaModelCatalog.chatModelNames` — models are chosen from the tag
    listing's `capabilities` array (`completion` means chat), with a
    name/family heuristic for older servers that omit it. Embedding-only
    models are skipped and counted in the provider detail.
    `AIProviderStatus.preferredChatModel` picks the first chat
    model deterministically; with none, Ask fails with
    `DocumentAssistantError.noChatCapableOllamaModel` and the pill says only
    embedding models are installed.
11. `ClaudeCodeClient.generate` — the prompt goes on stdin; argv is
    `claude -p --output-format text --no-session-persistence`. The
    `AIProviderKind` surface is unchanged.
12. `ReadingStateStore.load` and `save` (`coordinatedRead`, `coordinatedWrite`) — reads and writes go through
    `NSFileCoordinator`; a dataless iCloud placeholder triggers
    `startDownloadingUbiquitousItem` and returns `notYetDownloaded`, in which
    case the app starts empty, says so in the banner, and does not overwrite
    the synced file for that session. `KnowledgeRepository.rebuildIndexFromMarkdown`
    rebuilds the local SQLite index from the synced markdown at launch
    (`AppModel.rebuildKnowledgeIndexIfNeeded`), so notes written on
    another Mac become searchable. The storage strategy (which files sync) is
    unchanged and remains an open question.
13. `ReaderDocument.noteSourceIdentifier`, used by `ChatKnowledgeCapture` —
    notes are scoped by the full standardized path. Notes saved before this
    change under the bare filename are still shown for a file with that name
    (`ReaderDocument.legacyNoteSourceIdentifier` in `AppModel.refreshSavedNotesForSelectedDocument`), so old notes do not disappear.
14. `AppModel.triggerAutoSummary` — two kinds of auto-summary failure. A failed
    generation is a property of the page: it shows a dismissable
    "Auto-summary failed: <reason>" card, is cached per page, attempted once,
    shown again only when the reader returns to the page (including after
    switching documents), and never retried. Having no provider that can
    answer text — none available, or Ollama up with only embedding models —
    is not a property of the page and is never cached: one rule,
    `[AIProviderStatus].textAnswerBlocker`, decides it for the assistant, the
    summary task, and the card (`autoSummaryUnavailableReason`), so the
    notice clears the moment a chat-capable provider is detected and pages
    read meanwhile are summarised on their next visit.
    Only the failure card is dismissable: it reports an event. The
    "Auto-Summary Unavailable" notice states current app state, has no
    dismiss control, and stays exactly as long as it is true
    (`PageSummaryCardContent`).

Follow-ups noticed while fixing, not built:

- `PDFImagePlacementScanner.concatenateMatrixCallback` concatenates `cm` and form matrices in
  the wrong order (CTM × M instead of M × CTM), so nested transforms place
  figure crops wrongly. Only matters once the crop coordinates matter.
- `ClaudeCodeClient.generate` resolves `claude` via `/usr/bin/env`; a
  GUI-launched app inherits a minimal PATH, so the generation path can fail
  even when the probe (which falls back to a login shell) succeeds.
- `LiveDocumentHighlightStore.loadHighlights` still reads highlight files with
  `Data(contentsOf:)` on the MainActor, which is the same iCloud placeholder
  hazard as item 12 for highlights.
- `AppModel.triggerAutoSummary`'s cached-summary branch re-shows a dismissed summary card on every position
  update for the same page, including scrolls that only change the visible
  page set. The failure card is gated on a page change (item 14); the success
  card keeps the older behaviour.
- `LiveEPUBBookLoader.loadBook` still spawns `ditto` through `Process` with
  `waitUntilExit()` and no timeout, outside `ShellCommand`. It runs off the
  MainActor (item 7), so a hung `ditto` pins a pool thread rather than the UI.

Polish that matches “unpolished”: window min size 1120×760
(`CoReaderApp.body`); inspector and library closed at launch; EPUB
highlights are list rows only (`SelectionActionBar`); highlight
annotation colors are fixed calibrated RGB (`ReaderHighlightColor.annotationColor`),
not appearance-adaptive.

## Open Questions For Sushil

1. Who is the first user — Sushil only, students, or researchers?
2. Keep AI local-only (Ollama + Claude CLI), or bring back a localhost
   OpenAI-compatible adapter?
3. Is iCloud Drive a real requirement, or should notes and reading state stay
   in Application Support?
4. Is EPUB a first-class peer to PDF (in-book highlights, restored chapter), or
   PDF-first with EPUB as preview?
5. Should import copy files into an app-owned library so the original can move?
