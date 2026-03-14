# CoReader Logo Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Generate and integrate a premium CoReader logo across the macOS app icon and in-app branded surfaces.

**Architecture:** Use the OpenAI image generation workflow to produce a single master symbol, derive the macOS app icon set from that master, add a new asset catalog to the app target, and reuse the same symbol in the SwiftUI shell for consistent branding.

**Tech Stack:** OpenAI Image API via the `imagegen` skill CLI, Python tooling, SwiftUI, Xcode asset catalogs, XcodeGen

---

### Task 1: Generate the master symbol

**Files:**
- Create: `output/imagegen/coreader-logo-master.png`
- Create: `output/imagegen/`

**Step 1: Write the failing verification**

- Confirm there is no branded logo asset in the repo yet.

**Step 2: Run verification to prove the gap**

Run: `rg --files . | rg 'AppIcon|coreader-logo|Assets.xcassets'`

Expected: no app branding assets are present.

**Step 3: Generate the image**

- Use the approved prompt direction:
  - graphite background
  - brass open-book form
  - teal AI node orbit
  - symbol-only
  - vector-like, premium, macOS app icon composition

**Step 4: Validate output**

- Inspect the generated image locally and confirm it reads clearly at small sizes.

**Step 5: Commit**

```bash
git add output/imagegen/coreader-logo-master.png
git commit -m "feat: generate coreader logo master"
```

### Task 2: Build the app icon asset catalog

**Files:**
- Create: `Sources/CoReaderApp/Resources/Assets.xcassets/AppIcon.appiconset/...`
- Create: `Sources/CoReaderApp/Resources/Assets.xcassets/Contents.json`
- Create: `Sources/CoReaderApp/Resources/Assets.xcassets/CoReaderMark.imageset/...`
- Modify: `project.yml`

**Step 1: Write the failing verification**

- Confirm the app target does not yet contain a real asset catalog.

**Step 2: Run verification to prove it fails**

Run: `test -d Sources/CoReaderApp/Resources/Assets.xcassets/AppIcon.appiconset`

Expected: FAIL / missing directory.

**Step 3: Write minimal implementation**

- Add the asset catalog structure.
- Derive required macOS icon sizes from the master logo.
- Add a reusable branded image set for in-app use.
- Ensure `project.yml` includes the resources path.

**Step 4: Run verification**

Run: `xcodegen generate`

Expected: PASS with the resources included in the regenerated project.

**Step 5: Commit**

```bash
git add project.yml Sources/CoReaderApp/Resources/Assets.xcassets
git commit -m "feat: add coreader asset catalog"
```

### Task 3: Integrate the logo into the app shell

**Files:**
- Modify: `Sources/CoReaderApp/Features/ProviderStatus/ProviderStatusView.swift`
- Modify: `Sources/CoReaderApp/Features/Workspace/ReaderSidebarView.swift`
- Modify: `Sources/CoReaderApp/App/CoReaderApp.swift`

**Step 1: Write the failing verification**

- Add a narrow test or code-path check if practical; otherwise verify the current UI uses only text branding.

**Step 2: Run verification to confirm the gap**

Run: `rg -n 'Co-Reader|CoReader' Sources/CoReaderApp`

Expected: text-only branding with no reusable symbol asset usage.

**Step 3: Write minimal implementation**

- Add a small reusable SwiftUI brand mark view using the new asset.
- Integrate it in the app shell and sidebar/title surfaces without disturbing layout.

**Step 4: Run verification**

Run: `swift build`

Expected: PASS

**Step 5: Commit**

```bash
git add Sources/CoReaderApp/App/CoReaderApp.swift Sources/CoReaderApp/Features/ProviderStatus/ProviderStatusView.swift Sources/CoReaderApp/Features/Workspace/ReaderSidebarView.swift
git commit -m "feat: integrate coreader branding"
```

### Task 4: Full verification and ship

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

Expected: app launches successfully with the compiled asset catalog.

**Step 4: Commit**

```bash
git add .
git commit -m "feat: add coreader logo"
git push origin master
```
