# EPUB Selection And Highlights Design

## Goal

Bring EPUB reading up to parity with PDF selection so users can select text inside a chapter, ask questions about that exact passage, create notes, and save highlights into the existing Brain pipeline.

## Chosen Approach

Keep the `WKWebView` chapter renderer and add a JavaScript selection bridge.

- Inject a small script into each EPUB chapter page that watches DOM selection changes.
- Post normalized selection payloads back into Swift through `WKScriptMessageHandler`.
- Convert the payload into the existing `DocumentSelection` model so the current ask/highlight/note UI keeps working.
- Add persistent EPUB highlight records that are anchored by chapter index plus quoted text, then render them back into the chapter HTML with `<mark>` styling.

This keeps the current EPUB renderer intact, avoids a custom text engine, and lets the existing selection-driven workspace ship on EPUB quickly.

## Alternatives Considered

### 1. Replace `WKWebView` with a custom text renderer

This would make native selection easier to own, but it would throw away EPUB CSS/layout fidelity and create a much larger rendering project.

### 2. Capture only transient selections and skip persisted highlights

This would unblock ask/note actions, but it would still violate the user expectation that highlights survive document switches and relaunches.

### 3. Defer EPUB selection entirely

This leaves EPUB as a second-class reader, which is the exact gap users are feeling now.

## Architecture

### Selection bridge

Add a reusable EPUB web coordinator that:

- injects a user script at document start
- serializes the current DOM selection text and nearby container text
- reports selection clear/select events back to Swift

The Swift side should debounce duplicate selections and publish `nil` when the user collapses the range.

### Persistent highlight model

Extend the existing note/highlight persistence path so EPUB highlights store:

- document identifier
- chapter index
- quoted text
- optional note text

The app already scopes saved highlights by document, so EPUB can reuse the same sidebar/inspector UI with chapter labels instead of page labels.

### Highlight rendering

When a chapter loads, inject saved highlight ranges back into the DOM with a lightweight `<mark data-coreader-highlight>` wrapper.

The first checkpoint can match by exact text within the chapter body. This is not perfect for duplicate passages, but it is good enough to establish durable EPUB highlighting without building a full CFI system yet.

## UX Notes

- EPUB selection should surface the existing floating action bar exactly like PDF.
- Saved EPUB highlights should read as `Chapter N` everywhere the app currently says `Page N`.
- Chapter navigation must preserve or clear selection intentionally so stale selection state never leaks across chapters.

## Testing Strategy

- Unit tests for the selection payload normalizer.
- App model tests proving EPUB highlights persist with chapter labels.
- Preview/coordinator tests for turning script messages into `DocumentSelection`.
- Parser-free tests for applying saved highlights back into chapter HTML.

## Non-Goals

- EPUB CFI anchors
- multi-range or overlapping highlight editing
- full annotation sidebar for EPUB
- search across web articles
