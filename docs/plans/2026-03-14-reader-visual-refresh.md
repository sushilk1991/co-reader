# Reader Visual Refresh Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refresh the macOS reader UI with a calmer editorial palette and stronger hierarchy.

**Architecture:** Centralize the new palette in `ReaderTheme`, then restyle the main workspace containers and the most visible content panels to use consistent surface, border, and accent rules.

**Tech Stack:** SwiftUI, Observation, XcodeGen, Swift Testing

---

### Task 1: Replace the shared theme tokens

**Files:**
- Modify: `Sources/CoReaderApp/Features/Workspace/ReaderTheme.swift`

### Task 2: Rework shell hierarchy

**Files:**
- Modify: `Sources/CoReaderApp/Features/Workspace/ReaderWorkspaceView.swift`
- Modify: `Sources/CoReaderApp/Features/Workspace/ReaderToolbarView.swift`
- Modify: `Sources/CoReaderApp/Features/Workspace/ReaderSidebarView.swift`
- Modify: `Sources/CoReaderApp/Features/Workspace/ReaderInspectorView.swift`
- Modify: `Sources/CoReaderApp/Features/Workspace/DocumentPreviewPanel.swift`

### Task 3: Refresh the ask and support panels

**Files:**
- Modify: `Sources/CoReaderApp/Features/Workspace/DocumentChatPanel.swift`
- Modify: `Sources/CoReaderApp/Features/Workspace/ChatMessageBubble.swift`
- Modify: `Sources/CoReaderApp/Features/ProviderStatus/ProviderStatusCard.swift`
- Modify: `Sources/CoReaderApp/Features/Workspace/ImportedDocumentRow.swift`
- Modify: `Sources/CoReaderApp/Features/Workspace/ReaderNotesPanel.swift`
- Modify: `Sources/CoReaderApp/Features/Workspace/ReaderHighlightsPanel.swift`
- Modify: `Sources/CoReaderApp/Features/Workspace/ReaderVisualsPanel.swift`

### Task 4: Verify and checkpoint

**Files:**
- Verify build/test output only
