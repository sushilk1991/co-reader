# EPUB Reader Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a real macOS EPUB reading flow with chapter navigation and chapter-grounded AI context.

**Architecture:** Extract EPUB files into a local cache, parse the package manifest/spine into a lightweight `EPUBBook` model, render one section at a time in `WKWebView`, and feed section text back into the existing document context composer. This keeps the implementation native, deterministic, and testable without third-party frameworks.

**Tech Stack:** Swift 6, SwiftUI, WebKit, FoundationXML, macOS system archive tooling, Swift Testing

---

### Task 1: Add EPUB parser tests

**Files:**
- Create: `Tests/CoReaderAppTests/Core/Documents/EPUBBookLoaderTests.swift`

**Step 1: Write the failing tests**

- Add a test for resolving the OPF package path from a `container.xml` string.
- Add a test for parsing manifest/spine order from a minimal OPF string.
- Add a test for loading a tiny synthetic EPUB into an ordered `EPUBBook`.

**Step 2: Run test to verify it fails**

Run: `swift test --filter EPUBBookLoaderTests`

Expected: FAIL because the EPUB loader types do not exist yet.

**Step 3: Write minimal implementation**

- Create the parser and loader types needed only to make these tests pass.

**Step 4: Run test to verify it passes**

Run: `swift test --filter EPUBBookLoaderTests`

Expected: PASS

**Step 5: Commit**

```bash
git add Tests/CoReaderAppTests/Core/Documents/EPUBBookLoaderTests.swift Sources/CoReaderApp/Core/Documents/...
git commit -m "feat: add epub loader"
```

### Task 2: Hook EPUB context extraction into the AI pipeline

**Files:**
- Modify: `Sources/CoReaderApp/Core/Documents/LiveDocumentContextExtractor.swift`
- Test: `Tests/CoReaderAppTests/Core/Documents/EPUBDocumentContextExtractorTests.swift`

**Step 1: Write the failing test**

- Add a test proving an EPUB question uses current-section text instead of the placeholder excerpt.

**Step 2: Run test to verify it fails**

Run: `swift test --filter EPUBDocumentContextExtractorTests`

Expected: FAIL because EPUB extraction still returns a placeholder message.

**Step 3: Write minimal implementation**

- Load the EPUB book.
- Feed section texts into `DocumentContextComposer`.

**Step 4: Run test to verify it passes**

Run: `swift test --filter 'EPUBDocumentContextExtractorTests|DocumentContextComposerTests'`

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/CoReaderApp/Core/Documents/LiveDocumentContextExtractor.swift Tests/CoReaderAppTests/Core/Documents/EPUBDocumentContextExtractorTests.swift
git commit -m "feat: ground ai context in epub chapters"
```

### Task 3: Build the EPUB preview

**Files:**
- Create: `Sources/CoReaderApp/Features/Workspace/EPUBPreviewView.swift`
- Modify: `Sources/CoReaderApp/Features/Workspace/DocumentPreviewPanel.swift`
- Modify: `Sources/CoReaderApp/App/AppModel.swift`
- Test: `Tests/CoReaderAppTests/AppModelReaderStateTests.swift`

**Step 1: Write the failing test**

- Add a state test for chapter navigation if chapter index is stored in `AppModel`.

**Step 2: Run test to verify it fails**

Run: `swift test --filter AppModelReaderStateTests`

Expected: FAIL because EPUB reading position state does not exist yet.

**Step 3: Write minimal implementation**

- Add `EPUBPreviewView` with chapter picker and previous/next controls.
- Render the selected spine item in `WKWebView`.
- Update reading position callbacks for EPUB sections.

**Step 4: Run test to verify it passes**

Run: `swift test --filter AppModelReaderStateTests`

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/CoReaderApp/Features/Workspace/EPUBPreviewView.swift Sources/CoReaderApp/Features/Workspace/DocumentPreviewPanel.swift Sources/CoReaderApp/App/AppModel.swift Tests/CoReaderAppTests/AppModelReaderStateTests.swift
git commit -m "feat: render epub chapters in the workspace"
```

### Task 4: Full verification and app run

**Files:**
- Modify as needed from prior tasks

**Step 1: Run the full package test suite**

Run: `swift test`

Expected: PASS

**Step 2: Run strict macOS verification**

Run: `make agent-verify`

Expected: `** TEST SUCCEEDED **`

**Step 3: Launch the app**

Run: `./scripts/run_app_macos.sh --app-path /Users/sushil/Code/co-reader/build/DerivedData/CODEX/Build/Products/Debug/CoReader.app --background --replace-app-path`

Expected: the app process is running from the built `.app`.

**Step 4: Commit**

```bash
git add .
git commit -m "feat: add first-pass epub reader"
git push origin master
```
