# PDF Visual Workflow Design

## Goal

Add a native PDF visual workflow to Co-Reader so a reader can inspect extracted visuals, save them locally, and ask grounded diagram questions without leaving the reading session.

## Context

The current app already has a reader-first PDF workspace, page-aware text context, local Ollama and Claude routing, and Brain persistence for notes and highlights. What is missing is a visual path: there is no extractable image gallery, no saved figure workflow, and "Explain Diagram" still behaves like a text-only action.

## Approaches Considered

### 1. Page Snapshot Workflow

Render full PDF pages as images, expose them as visuals, and use those snapshots for export and AI explanation.

Pros:
- Simple and reliable.
- Works on any PDF page.

Cons:
- Not true image extraction.
- Produces oversized visuals.
- Makes "save image" ambiguous because the output is really a page render.

### 2. Embedded Image Extraction With Snapshot Fallback

Extract embedded PDF image assets when possible. If a page has no directly extractable image streams, allow a rendered page snapshot fallback for diagram explanation and export.

Pros:
- Matches the product requirement much better.
- Gives the user a true visual gallery when the PDF contains embedded figures.
- Still keeps the experience robust on harder PDFs.

Cons:
- More Core Graphics work.
- Some PDF image formats may still need fallback handling.

### 3. External CLI Extraction

Shell out to tools like `pdfimages` when available and treat the result as the gallery source.

Pros:
- Fast to prototype.

Cons:
- Fragile and environment-dependent.
- Not acceptable as the native default workflow.

## Recommendation

Use approach 2.

This keeps the app native and honest: extract real PDF visuals where we can, use a page-render fallback where extraction is not available, and make the UI explicit about which visuals are extracted assets versus page renders.

## Design

### Extraction Layer

Add a PDF visual extraction service in the document core. It will:

- Walk PDF pages and collect visual assets.
- Persist enough metadata to identify page number, source kind, pixel size, and a stable export filename.
- Extract embedded image streams where feasible.
- Render a page snapshot fallback for the active page when the user requests a diagram explanation and no embedded visual is selected.

The first checkpoint is PDF-only. EPUB visual extraction remains out of scope for this loop.

### Reader UX

Add a `Visuals` inspector tab next to `Ask`, `Notes`, and `Highlights`.

The tab will show:

- Extracted visual thumbnails for the current document.
- Page number and extraction type.
- A selected visual preview.
- `Explain`, `Save PNG`, and `Reveal in Finder` actions.

The existing `Explain Diagram` quick action will become smarter:

- If a visual is selected, use that visual.
- Else if the current PDF page has a visual, use the nearest visual on that page.
- Else fall back to a rendered image of the current page with a clear prompt that it is a page snapshot.

### AI Flow

Extend the Ollama generation client to optionally send one image payload with the prompt.

Rules:

- Prefer a vision-capable Ollama model when the request includes an image.
- If no usable Ollama model is available, fail clearly instead of pretending a text-only answer is a visual explanation.
- Claude CLI remains text-only in this checkpoint.

### Persistence

Persist saved visual exports to a local `Exports/` folder inside the app data area, not to the Brain note index. The Brain remains for notes, highlights, and chat captures. Visual metadata for the current session can stay in memory for this loop.

### Error Handling

Handle these cases explicitly:

- PDF has no extractable images.
- Extracted image encoding cannot be converted to a displayable/exportable asset.
- No vision-capable Ollama model is available.
- Save/export fails due to filesystem issues.

### Testing

Use TDD for:

- PDF visual extraction on a synthetic PDF fixture.
- Visual selection and fallback behavior in the app model.
- Vision request routing in the Ollama client.
- Export filename and destination handling.
