# Co-Reader Reader-First Redesign

**Context**

The current app proves out local AI wiring, PDF import, and note persistence, but the reading experience is weak. The document loses too much width to permanent sidebars, PDF interactions are read-only, and quick actions use a single flat excerpt that collapses on long books. The redesign needs to make reading primary and AI secondary until the user explicitly asks for help.

**Goals**

- Make the document the dominant surface.
- Hide library and AI chrome by default, but keep them one click away.
- Turn PDF selection into a first-class interaction that powers asking, highlighting, and notes.
- Replace the flat whole-document excerpt model with a smarter context pipeline built from selection, visible page text, and chunked retrieval.
- Clarify the relationship between AI answers, saved notes, and the local Brain.

**Non-Goals For This Checkpoint**

- Full EPUB rendering.
- OCR for scanned PDFs.
- True multimodal vision analysis.
- Chapter inference that depends on full semantic structure extraction.

**Recommended Approach**

Use a reader-first single-window workspace with a collapsible library rail and a collapsible right inspector. The center pane owns the experience. A contextual selection bar appears only when the user selects PDF text. AI actions consume the tightest relevant context first:

1. explicit text selection
2. current page excerpt
3. retrieved document chunks

This keeps the UI quiet while making AI answers far more useful on long documents.

**Visual Direction**

- Base palette: warm paper, charcoal text, muted slate surfaces.
- Accent palette: teal for active tools, brass for saved knowledge/highlights.
- Default appearance: bright layered surfaces rather than muddy dark panels.
- Materials: subtle macOS materials for chrome, stronger paper contrast in the reader.
- Typography: larger document title treatment, quieter supporting metadata, clearer hierarchy for tools.

**Layout**

- Top bar:
  - sidebar toggle
  - document title
  - provider readiness pill
  - inspector toggle
- Left rail:
  - hidden by default
  - import button, recent documents, provider summary
- Main reader:
  - dominant PDF canvas
  - optional chapter/page summary strip
  - contextual selection actions
- Right inspector:
  - hidden by default
  - segmented tabs for `Ask`, `Notes`, and `Highlights`

**Interaction Model**

- No document loaded:
  - polished import state with short explanation and primary import call-to-action
- Document loaded:
  - chrome recedes
  - library stays hidden unless explicitly opened
- Text selected in PDF:
  - selection state is captured in app state
  - contextual actions appear: `Ask`, `Highlight`, `Note`, `Save to Brain`
- Notes:
  - can be created from a selection or freeform in the inspector
  - are saved as Markdown and indexed in SQLite
- Highlights:
  - are stored as note-like artifacts with source text, document, page, and timestamp

**Smart Context Pipeline**

The AI layer should stop treating a book like one long blob. Context should be composed in priority order:

1. **Selection context**
   - selected text
   - surrounding text window
   - page index
2. **Visible reading context**
   - current page text
   - nearby page text
3. **Retrieved chunk context**
   - document chunks scored against the user question or quick action prompt

Quick actions use this pipeline differently:

- `Summarize`: summarize top chunks or the current chapter/page cluster, then merge.
- `Generate Code`: selection-first if present, otherwise retrieve chunks most related to implementation patterns.
- `Explain Diagram`: use the current page/selection context now; leave true image extraction for the next checkpoint.
- `Quiz Me`: generate from selected section if present, otherwise current reading cluster.

**Data Model Additions**

- `DocumentChunk`: id, document id, page range, text, token-ish size
- `DocumentSelection`: selected text, surrounding text, page index, bounds metadata if available
- `ReaderHighlight`: document id, page index, quoted text, note text, createdAt
- `InspectorTab`: ask, notes, highlights

**Testing Strategy**

- Unit-test chunk building and context selection rules.
- Unit-test selection-aware quick actions and note creation.
- Keep app model behavior under test for inspector toggles and selection workflows.
- Verify the macOS app with Xcode build/test and launch after the redesign lands.
