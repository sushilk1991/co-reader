# Reader-First Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild Co-Reader into a reader-first macOS workspace with collapsible tools, selection-driven notes/highlights, and smarter AI context for long documents.

**Architecture:** Keep the app model as the orchestration point, add explicit reader UI state and selection/highlight models, and move document context generation from a flat extractor to chunked, priority-based context assembly. The PDF view becomes interactive by reporting current selection and visible page metadata back into SwiftUI state.

**Tech Stack:** Swift 6, SwiftUI, PDFKit, Foundation, SQLite3, XCTest, xcodebuild

---

### Task 1: Add the redesign state models

**Files:**
- Create: `Sources/CoReaderApp/Core/Documents/DocumentChunk.swift`
- Create: `Sources/CoReaderApp/Core/Documents/DocumentSelection.swift`
- Create: `Sources/CoReaderApp/Core/Documents/ReaderHighlight.swift`
- Create: `Sources/CoReaderApp/App/InspectorTab.swift`
- Modify: `Sources/CoReaderApp/App/AppModel.swift`
- Test: `Tests/CoReaderAppTests/AppModelReaderStateTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
func test_readerStartsInReaderFirstMode() async

@MainActor
func test_selectionEnablesContextualActionsAndHighlightCapture() async
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter AppModelReaderStateTests`
Expected: FAIL because the reader state and selection models do not exist.

**Step 3: Write minimal implementation**

Add inspector/sidebar state, selection storage, note draft state, and highlight capture behavior to `AppModel`.

**Step 4: Run test to verify it passes**

Run: `swift test --filter AppModelReaderStateTests`
Expected: PASS

**Step 5: Commit**

```bash
git add .
git commit -m "feat: add reader workspace state"
```

### Task 2: Add chunked context assembly

**Files:**
- Create: `Sources/CoReaderApp/Core/Documents/DocumentChunkBuilder.swift`
- Create: `Sources/CoReaderApp/Core/Documents/DocumentContextComposer.swift`
- Modify: `Sources/CoReaderApp/Core/Documents/LiveDocumentContextExtractor.swift`
- Modify: `Sources/CoReaderApp/Core/AI/DocumentAssistant.swift`
- Test: `Tests/CoReaderAppTests/Core/Documents/DocumentContextComposerTests.swift`
- Test: `Tests/CoReaderAppTests/Core/AI/DocumentAssistantContextTests.swift`

**Step 1: Write the failing test**

```swift
func test_composer_prefers_selection_then_visible_page_then_chunks() throws
func test_quick_action_uses_chunked_context_for_long_documents() async throws
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter DocumentContextComposerTests`
Expected: FAIL because the composer and chunk rules do not exist.

**Step 3: Write minimal implementation**

Split extracted PDF text into page-aware chunks, compose prompts from selection/visible page/retrieved chunks, and route quick actions through the composer.

**Step 4: Run test to verify it passes**

Run: `swift test --filter DocumentContextComposerTests`
Run: `swift test --filter DocumentAssistantContextTests`
Expected: PASS

**Step 5: Commit**

```bash
git add .
git commit -m "feat: add smart document context composition"
```

### Task 3: Make the PDF reader interactive

**Files:**
- Modify: `Sources/CoReaderApp/Features/Workspace/PDFPreviewView.swift`
- Modify: `Sources/CoReaderApp/Features/Workspace/DocumentPreviewPanel.swift`
- Create: `Sources/CoReaderApp/Features/Workspace/SelectionActionBar.swift`
- Test: `Tests/CoReaderAppTests/AppModelSelectionWorkflowTests.swift`

**Step 1: Write the failing test**

```swift
@MainActor
func test_creatingSelectionNoteStoresMarkdownAndIndexEntry() async throws
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter AppModelSelectionWorkflowTests`
Expected: FAIL because the selection workflow is not wired into note capture.

**Step 3: Write minimal implementation**

Teach `PDFPreviewView` to report selected text and page information, surface a contextual action bar, and wire `Highlight`, `Note`, and `Ask` actions into the app model.

**Step 4: Run test to verify it passes**

Run: `swift test --filter AppModelSelectionWorkflowTests`
Expected: PASS

**Step 5: Commit**

```bash
git add .
git commit -m "feat: add pdf selection actions"
```

### Task 4: Replace the old three-pane shell with a reader-first workspace

**Files:**
- Modify: `Sources/CoReaderApp/Features/ProviderStatus/ProviderStatusView.swift`
- Create: `Sources/CoReaderApp/Features/Workspace/ReaderWorkspaceView.swift`
- Create: `Sources/CoReaderApp/Features/Workspace/ReaderToolbarView.swift`
- Create: `Sources/CoReaderApp/Features/Workspace/ReaderSidebarView.swift`
- Create: `Sources/CoReaderApp/Features/Workspace/ReaderInspectorView.swift`
- Create: `Sources/CoReaderApp/Features/Workspace/ReaderNotesPanel.swift`
- Create: `Sources/CoReaderApp/Features/Workspace/ReaderHighlightsPanel.swift`
- Modify: `Sources/CoReaderApp/App/CoReaderApp.swift`
- Test: `Tests/CoReaderAppTests/SmokeTests.swift`

**Step 1: Write the failing test**

```swift
func test_appModelHasExpectedLaunchCopy() async throws
```

Update it to assert reader-first copy and tool visibility expectations.

**Step 2: Run test to verify it fails**

Run: `swift test --filter SmokeTests`
Expected: FAIL because the launch copy and workspace assumptions changed.

**Step 3: Write minimal implementation**

Replace the old always-on sidebars with collapsible reader chrome, add inspector tabs, and apply the new visual system.

**Step 4: Run test to verify it passes**

Run: `swift test --filter SmokeTests`
Expected: PASS

**Step 5: Commit**

```bash
git add .
git commit -m "feat: redesign app as reader-first workspace"
```

### Task 5: Verify the integrated redesign

**Files:**
- Modify only as needed based on failures

**Step 1: Run the Swift package tests**

Run: `swift test`
Expected: PASS

**Step 2: Run the macOS Xcode verification**

Run: `make agent-verify`
Expected: PASS

**Step 3: Launch the app**

Run: `./scripts/run_app_macos.sh --app-path build/DerivedData/CODEX/Build/Products/Debug/CoReader.app --background --replace-app-path`
Expected: the app launches successfully

**Step 4: Commit any final integration fixes**

```bash
git add .
git commit -m "feat: ship reader-first redesign"
```
