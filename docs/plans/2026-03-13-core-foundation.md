# Co-Reader Core Foundation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Scaffold the macOS app foundation, then ship local AI provider discovery and dual-storage knowledge persistence with verified checkpoint commits.

**Architecture:** The app uses a Swift package with a SwiftUI macOS executable target plus a separate test target. App features depend on protocol-backed services in `Core/AI` and `Core/Knowledge`, which allows isolated TDD and later UI expansion.

**Tech Stack:** Swift 6.2, SwiftUI, Foundation, URLSession, Process, SQLite3, XCTest, git

---

### Task 1: Create the app skeleton

**Files:**
- Create: `Package.swift`
- Create: `Sources/CoReaderApp/App/CoReaderApp.swift`
- Create: `Sources/CoReaderApp/App/AppModel.swift`
- Create: `Sources/CoReaderApp/Features/ProviderStatus/ProviderStatusView.swift`
- Create: `.gitignore`

**Step 1: Write the failing test**

No behavior test for the shell. Create a compile-ready package structure instead.

**Step 2: Run test to verify it fails**

Run: `swift test`
Expected: FAIL because the package manifest and sources do not exist yet.

**Step 3: Write minimal implementation**

Create a package manifest, a SwiftUI macOS app entry point, and a simple provider status view bound to an observable model.

**Step 4: Run test to verify it passes**

Run: `swift test`
Expected: PASS with zero feature tests initially.

**Step 5: Commit**

```bash
git add .
git commit -m "chore: scaffold co-reader app foundation"
```

### Task 2: Add provider discovery

**Files:**
- Create: `Sources/CoReaderApp/Core/AI/AIProvider.swift`
- Create: `Sources/CoReaderApp/Core/AI/AIProviderDiscovery.swift`
- Create: `Sources/CoReaderApp/Core/AI/OllamaClient.swift`
- Create: `Sources/CoReaderApp/Core/AI/ClaudeCLIProbe.swift`
- Modify: `Sources/CoReaderApp/App/AppModel.swift`
- Modify: `Sources/CoReaderApp/Features/ProviderStatus/ProviderStatusView.swift`
- Test: `Tests/CoReaderAppTests/Core/AI/AIProviderDiscoveryTests.swift`

**Step 1: Write the failing test**

```swift
func test_discovery_reports_running_ollama_and_claude() async throws
func test_discovery_marks_provider_unavailable_when_probe_fails() async throws
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter AIProviderDiscoveryTests`
Expected: FAIL because discovery types do not exist.

**Step 3: Write minimal implementation**

Add protocol-backed probes, normalize into a provider status model, and expose the result through `AppModel`.

**Step 4: Run test to verify it passes**

Run: `swift test --filter AIProviderDiscoveryTests`
Expected: PASS

**Step 5: Commit**

```bash
git add .
git commit -m "feat: add local ai provider discovery"
```

### Task 3: Add dual-storage knowledge persistence

**Files:**
- Create: `Sources/CoReaderApp/Core/Knowledge/KnowledgeNote.swift`
- Create: `Sources/CoReaderApp/Core/Knowledge/MarkdownKnowledgeStore.swift`
- Create: `Sources/CoReaderApp/Core/Knowledge/SQLiteKnowledgeIndex.swift`
- Create: `Sources/CoReaderApp/Core/Knowledge/KnowledgeRepository.swift`
- Test: `Tests/CoReaderAppTests/Core/Knowledge/KnowledgeRepositoryTests.swift`

**Step 1: Write the failing test**

```swift
func test_save_writes_markdown_and_indexes_metadata() throws
func test_search_returns_recent_matching_notes() throws
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter KnowledgeRepositoryTests`
Expected: FAIL because the storage types do not exist.

**Step 3: Write minimal implementation**

Write note files to disk, create SQLite schema on demand, and provide a simple search API returning indexed note summaries.

**Step 4: Run test to verify it passes**

Run: `swift test --filter KnowledgeRepositoryTests`
Expected: PASS

**Step 5: Commit**

```bash
git add .
git commit -m "feat: add dual-storage knowledge repository"
```

### Task 4: Verify the integrated baseline

**Files:**
- Modify only as needed based on failures

**Step 1: Run the full verification suite**

Run: `swift test`
Expected: PASS

**Step 2: Build the app**

Run: `swift build`
Expected: PASS

**Step 3: Commit any integration fixes**

```bash
git add .
git commit -m "chore: stabilize co-reader foundation"
```
