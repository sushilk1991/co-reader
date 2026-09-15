# CoReader

macOS 15+ SwiftUI reader. Not iOS. Product/UX: `PRODUCT_INTENT.md`.

`Package.swift` and `project.yml` both compile `Sources/CoReaderApp` and
`Tests/CoReaderAppTests`. SwiftPM runs unit tests. The `.app` is
`CoReader.xcodeproj`, generated from `project.yml`.

## Commands

```bash
xcodegen generate --spec project.yml
swift test
make test
make build-and-run-background
```

Definition of done: `swift test` and `make test` both exit 0. Run the GUI only
via `make build-and-run-background`, which launches the Debug `.app` through
`scripts/run_app_macos.sh`.

## Guardrails

- Destination is `platform=macOS`. After adding a Swift file under
  `Sources/CoReaderApp/` or `Tests/CoReaderAppTests/`, rerun
  `xcodegen generate --spec project.yml` so the Xcode target lists it.
- Keep `Package.swift` and `project.yml` version/deployment fields in
  agreement when you bump them (Swift 6 language mode, macOS 15).
- Tests are Swift Testing (`import Testing`, `@Test`), e.g.
  `Tests/CoReaderAppTests/AppModelReaderStateTests.swift`.
- Orchestration lives in `Sources/CoReaderApp/App/AppModel.swift`. Views
  under `Features/` call that model; they do not open SQLite or HTTP
  themselves. PDFKit's `PDFDocument(url:)` in the preview views is the one
  existing exception.
- Local providers only (Ollama, Claude CLI in `AIProviderKind`). Keep
  `project.yml` `platform: macOS`.
- Nothing blocking on the MainActor: PDFKit page walks and file reads go
  through `Core/Concurrency/BlockingWork.swift` (cancellable, reports
  progress); child processes go through `ShellCommand`, which always carries
  a timeout. `PRODUCT_INTENT.md` "Current state" lists the defects this
  prevents and the known follow-ups.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
