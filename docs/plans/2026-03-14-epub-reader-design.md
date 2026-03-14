# EPUB Reader Design

## Goal

Replace the current EPUB placeholder with a real macOS reading experience that can open an `.epub`, render its spine content natively inside the workspace, and expose section text so AI prompts stay grounded to the current chapter instead of a generic placeholder message.

## Chosen Approach

Build a first-pass chapter-based EPUB engine instead of a fake continuous renderer.

- Extract the EPUB into a local cache directory using system tooling.
- Parse `META-INF/container.xml` and the OPF manifest/spine to build an ordered list of sections.
- Render one spine section at a time in `WKWebView`, with previous/next and chapter picker controls.
- Extract plain text per section so the document context system can answer against the current chapter.

This keeps the implementation native enough for macOS, preserves existing EPUB CSS/images, and avoids introducing third-party ZIP or HTML parsing dependencies.

## Alternatives Considered

### 1. Concatenate all EPUB XHTML into one giant HTML file

This would mimic the PDF continuous scroll feel, but it creates brittle asset rewriting problems for CSS, images, and relative links. It also makes context extraction less precise because the app loses the document’s real reading order boundaries.

### 2. Ship an EPUB placeholder until a full engine exists

This is the current state and it does not meet the app’s core promise. EPUB import without rendering is not a reader.

### 3. Use a third-party EPUB framework

This would speed up rendering, but it adds dependency weight and cuts across the current no-third-party foundation of the app. For this checkpoint, the system stack is enough.

## Architecture

### EPUB extraction and parsing

Add a small EPUB loader that:

- extracts the archive into `Application Support/CoReader/EPUBCache/...`
- resolves the OPF path from `container.xml`
- parses the manifest and spine
- returns an ordered `EPUBBook` model containing section file URLs and plain text

The parser only needs the subset required for rendering and grounded AI context: package path, spine order, section URLs, and best-effort section titles.

### EPUB rendering

Add an `EPUBPreviewView` backed by `WKWebView`.

- The SwiftUI shell will own the selected chapter index.
- The web view loads the selected spine file with read access to the extracted EPUB directory.
- The preview toolbar shows chapter navigation and a compact “Chapter N of M” indicator.

The first checkpoint will not attempt text selection bridging from `WKWebView` into highlights. Reading and chapter-grounded AI context are the priority.

### AI context

Upgrade `LiveDocumentContextExtractor` so EPUB questions use the loaded section texts.

- If the reader is on a chapter, compose context from that chapter first.
- If no chapter is selected, fall back to the first meaningful sections.
- Preserve the current PDF path unchanged.

## UX Notes

- EPUB should feel like a real document mode, not a side feature.
- The preview area should reuse the reader’s existing chrome and typography.
- Loading failures need a concrete error message inside the preview card, not a blank view.

## Testing Strategy

- Parser tests for `container.xml` and OPF spine resolution.
- Integration-style loader test for a small synthetic EPUB fixture.
- Context extractor test proving EPUB questions use chapter text.
- Preview state tests for chapter navigation if the logic lives outside the view.

## Non-Goals For This Checkpoint

- EPUB text highlighting and note capture
- EPUB image extraction
- TOC nesting, bookmarks, or annotation sync
- perfect support for every malformed EPUB in the wild
