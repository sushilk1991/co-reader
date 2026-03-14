# EPUB Selection And Highlights Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add EPUB text selection, ask/highlight/note actions, and durable chapter-based highlight rendering.

**Architecture:** Extend the existing `WKWebView` EPUB renderer with a JavaScript bridge that publishes DOM selections into Swift, persist EPUB highlights through the current Brain pipeline, then re-inject saved highlights into chapter HTML when a section loads.

**Tech Stack:** Swift 6, SwiftUI, WebKit, JavaScript injection, Swift Testing

---

### Task 1: Add selection bridge tests

**Files:**
- Create: `Tests/CoReaderAppTests/Core/Documents/EPUBSelectionBridgeTests.swift`
- Create: `Sources/CoReaderApp/Core/Documents/EPUBSelectionPayload.swift`

**Step 1: Write the failing test**

- Add tests for decoding a DOM selection payload into `DocumentSelection`.
- Add tests for dropping empty or whitespace-only selections.

**Step 2: Run test to verify it fails**

Run: `swift test --filter EPUBSelectionBridgeTests`

Expected: FAIL because the payload bridge types do not exist yet.

**Step 3: Write minimal implementation**

- Create the payload type and normalization helper used by the webview coordinator.

**Step 4: Run test to verify it passes**

Run: `swift test --filter EPUBSelectionBridgeTests`

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/CoReaderApp/Core/Documents/EPUBSelectionPayload.swift Tests/CoReaderAppTests/Core/Documents/EPUBSelectionBridgeTests.swift
git commit -m "feat: decode epub selection payloads"
```

### Task 2: Wire EPUB selection into the preview

**Files:**
- Modify: `Sources/CoReaderApp/Features/Workspace/EPUBPreviewView.swift`
- Test: `Tests/CoReaderAppTests/Core/Documents/EPUBSelectionBridgeTests.swift`

**Step 1: Write the failing test**

- Add a test that proves a valid selection payload becomes a `DocumentSelection`.

**Step 2: Run test to verify it fails**

Run: `swift test --filter EPUBSelectionBridgeTests`

Expected: FAIL because the preview bridge is not publishing selections yet.

**Step 3: Write minimal implementation**

- Inject the selection script.
- Forward messages into Swift.
- Publish selection clear/select events through `onSelectionChange`.

**Step 4: Run test to verify it passes**

Run: `swift test --filter EPUBSelectionBridgeTests`

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/CoReaderApp/Features/Workspace/EPUBPreviewView.swift Tests/CoReaderAppTests/Core/Documents/EPUBSelectionBridgeTests.swift
git commit -m "feat: bridge epub text selection"
```

### Task 3: Persist and render EPUB highlights

**Files:**
- Modify: `Sources/CoReaderApp/App/AppModel.swift`
- Modify: `Sources/CoReaderApp/Features/Workspace/EPUBPreviewView.swift`
- Modify: `Tests/CoReaderAppTests/AppModelReaderStateTests.swift`
- Create: `Tests/CoReaderAppTests/Core/Documents/EPUBHighlightRenderingTests.swift`

**Step 1: Write the failing tests**

- Add an app model test proving an EPUB selection saves a highlight with chapter context.
- Add a rendering test proving saved highlight text is wrapped back into the chapter HTML.

**Step 2: Run test to verify it fails**

Run: `swift test --filter 'EPUBHighlightRenderingTests|AppModelReaderStateTests'`

Expected: FAIL because EPUB highlights are not rendered back into the web content yet.

**Step 3: Write minimal implementation**

- Reuse the current highlight persistence path.
- Render saved chapter highlights back into HTML with `<mark>`.
- Keep chapter labels in selection/highlight surfaces.

**Step 4: Run test to verify it passes**

Run: `swift test --filter 'EPUBHighlightRenderingTests|AppModelReaderStateTests'`

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/CoReaderApp/App/AppModel.swift Sources/CoReaderApp/Features/Workspace/EPUBPreviewView.swift Tests/CoReaderAppTests/AppModelReaderStateTests.swift Tests/CoReaderAppTests/Core/Documents/EPUBHighlightRenderingTests.swift
git commit -m "feat: persist epub highlights"
```

### Task 4: Verify and ship

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

Expected: the built app launches and the process is visible in `ps`.

**Step 4: Commit**

```bash
git add .
git commit -m "feat: add epub highlight capture"
git push origin master
```
