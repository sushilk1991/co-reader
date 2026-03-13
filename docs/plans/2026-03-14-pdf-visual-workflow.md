# PDF Visual Workflow Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a native PDF visual workflow that extracts visuals from PDFs, surfaces them in the reader, and powers diagram explanation and export actions.

**Architecture:** Add a PDF extraction service in the document core, store reader visual state in `AppModel`, surface it through a new inspector tab, and extend the Ollama client to support image-backed requests for diagram explanations. Keep the first checkpoint PDF-only and use a fallback page snapshot when embedded image extraction is unavailable.

**Tech Stack:** Swift 6, SwiftUI, PDFKit, Core Graphics, AppKit, SQLite-backed Brain, Ollama local HTTP API

---

### Task 1: Document the Feature Checkpoint

**Files:**
- Create: `docs/plans/2026-03-14-pdf-visual-workflow-design.md`
- Create: `docs/plans/2026-03-14-pdf-visual-workflow.md`

**Step 1: Save the design and implementation plan**

Write the two plan documents for the PDF visual workflow.

**Step 2: Commit the docs checkpoint**

Run:

```bash
git add docs/plans/2026-03-14-pdf-visual-workflow-design.md docs/plans/2026-03-14-pdf-visual-workflow.md
git commit -m "docs: plan pdf visual workflow"
```

### Task 2: Add Failing Extraction Tests

**Files:**
- Create: `Tests/CoReaderAppTests/Core/Documents/PDFVisualExtractorTests.swift`
- Modify: `Tests/CoReaderAppTests/AppModelReaderStateTests.swift`

**Step 1: Write the failing test**

Add tests for:

- extracting at least one visual from a synthetic PDF fixture,
- preserving page numbers and export filenames,
- diagram fallback behavior in the app model.

**Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter 'PDFVisualExtractorTests|AppModelReaderStateTests'
```

Expected: FAIL because the extractor and visual state do not exist yet.

**Step 3: Commit the red test checkpoint if useful**

```bash
git add Tests/CoReaderAppTests/Core/Documents/PDFVisualExtractorTests.swift Tests/CoReaderAppTests/AppModelReaderStateTests.swift
git commit -m "test: define pdf visual workflow"
```

### Task 3: Implement the PDF Visual Core

**Files:**
- Create: `Sources/CoReaderApp/Core/Documents/DocumentVisualAsset.swift`
- Create: `Sources/CoReaderApp/Core/Documents/DocumentVisualAssetSelection.swift`
- Create: `Sources/CoReaderApp/Core/Documents/PDFVisualExtractor.swift`
- Modify: `Sources/CoReaderApp/App/AppModel.swift`
- Modify: `Sources/CoReaderApp/Core/Documents/LiveDocumentContextExtractor.swift`

**Step 1: Write minimal implementation**

Implement:

- a visual asset model,
- a PDF extractor that walks pages and returns displayable visual assets,
- app model state for extracted visuals and selected visual,
- document activation hooks that refresh the visual list.

**Step 2: Run focused tests**

Run:

```bash
swift test --filter 'PDFVisualExtractorTests|AppModelReaderStateTests'
```

Expected: PASS

**Step 3: Commit**

```bash
git add Sources/CoReaderApp/Core/Documents/DocumentVisualAsset.swift Sources/CoReaderApp/Core/Documents/DocumentVisualAssetSelection.swift Sources/CoReaderApp/Core/Documents/PDFVisualExtractor.swift Sources/CoReaderApp/App/AppModel.swift Sources/CoReaderApp/Core/Documents/LiveDocumentContextExtractor.swift Tests/CoReaderAppTests/Core/Documents/PDFVisualExtractorTests.swift Tests/CoReaderAppTests/AppModelReaderStateTests.swift
git commit -m "feat: extract pdf visual assets"
```

### Task 4: Add Vision Request Support

**Files:**
- Modify: `Sources/CoReaderApp/Core/AI/OllamaGenerating.swift`
- Modify: `Sources/CoReaderApp/Core/AI/OllamaGenerationClient.swift`
- Modify: `Sources/CoReaderApp/Core/AI/DocumentAssistant.swift`
- Modify: `Sources/CoReaderApp/Core/AI/DocumentAssisting.swift`
- Modify: `Tests/CoReaderAppTests/Core/AI/DocumentAssistantTests.swift`

**Step 1: Write the failing test**

Add a test that expects the visual explanation path to forward an image payload to the Ollama client and to fail clearly when no image-capable local model is available.

**Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter DocumentAssistantTests
```

Expected: FAIL because the image payload path does not exist.

**Step 3: Write minimal implementation**

Extend the Ollama request schema to optionally include image data and update `DocumentAssistant` to call that path for diagram explanation requests.

**Step 4: Run test to verify it passes**

Run:

```bash
swift test --filter DocumentAssistantTests
```

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/CoReaderApp/Core/AI/OllamaGenerating.swift Sources/CoReaderApp/Core/AI/OllamaGenerationClient.swift Sources/CoReaderApp/Core/AI/DocumentAssistant.swift Sources/CoReaderApp/Core/AI/DocumentAssisting.swift Tests/CoReaderAppTests/Core/AI/DocumentAssistantTests.swift
git commit -m "feat: add ollama vision requests"
```

### Task 5: Build the Reader Visuals UI

**Files:**
- Modify: `Sources/CoReaderApp/App/InspectorTab.swift`
- Create: `Sources/CoReaderApp/Features/Workspace/ReaderVisualsPanel.swift`
- Modify: `Sources/CoReaderApp/Features/Workspace/ReaderInspectorView.swift`
- Modify: `Sources/CoReaderApp/Features/Workspace/DocumentPreviewPanel.swift`
- Modify: `Sources/CoReaderApp/Features/Workspace/DocumentChatPanel.swift`
- Modify: `Sources/CoReaderApp/Features/Workspace/ReaderToolbarView.swift`

**Step 1: Write the failing test**

Add app model tests for selecting a visual, exporting it, and preferring it for diagram explanations.

**Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter AppModelReaderStateTests
```

Expected: FAIL because visual selection/export state is not wired.

**Step 3: Write minimal UI and state wiring**

Add the `Visuals` tab, thumbnail list, preview pane, and actions:

- `Explain`
- `Save PNG`
- `Reveal`

**Step 4: Run focused tests**

Run:

```bash
swift test --filter AppModelReaderStateTests
```

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/CoReaderApp/App/InspectorTab.swift Sources/CoReaderApp/Features/Workspace/ReaderVisualsPanel.swift Sources/CoReaderApp/Features/Workspace/ReaderInspectorView.swift Sources/CoReaderApp/Features/Workspace/DocumentPreviewPanel.swift Sources/CoReaderApp/Features/Workspace/DocumentChatPanel.swift Sources/CoReaderApp/Features/Workspace/ReaderToolbarView.swift Tests/CoReaderAppTests/AppModelReaderStateTests.swift
git commit -m "feat: add reader visuals panel"
```

### Task 6: Full Verification and Ship Checkpoint

**Files:**
- Modify: `CoReader.xcodeproj/project.pbxproj`
- Modify: `.gitignore` if needed

**Step 1: Regenerate the Xcode project if new files were added**

Run:

```bash
xcodegen generate
```

**Step 2: Run package tests**

Run:

```bash
swift test
```

Expected: PASS

**Step 3: Run macOS build and tests**

Run:

```bash
make agent-verify
```

Expected: `** TEST SUCCEEDED **`

**Step 4: Launch the macOS app**

Run:

```bash
./scripts/run_app_macos.sh --app-path /Users/sushil/Code/co-reader/build/DerivedData/CODEX/Build/Products/Debug/CoReader.app --background --replace-app-path
ps -axo pid=,comm= | rg 'CoReader(\\.app/Contents/MacOS/CoReader)?$|/CoReader.app/Contents/MacOS/CoReader'
```

Expected: the debug `CoReader.app` process is visible.

**Step 5: Commit**

```bash
git add .
git commit -m "feat: add pdf visual workflow"
```
