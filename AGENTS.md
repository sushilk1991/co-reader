# CoReader

macOS 15+ SwiftUI reader. Not iOS. Product/UX: `PRODUCT_INTENT.md`.

`Package.swift` and `project.yml` both compile `Sources/CoReaderApp` and
`Tests/CoReaderAppTests`. SwiftPM runs unit tests. The `.app` is
`CoReader.xcodeproj`, generated from `project.yml`.

## Commands

```bash
xcodegen generate --spec project.yml
swift test
AGENT_NAME=coreader-intent ./scripts/xcbuild.sh --action test -- -project CoReader.xcodeproj -scheme CoReaderApp -destination 'platform=macOS' -derivedDataPath build/DerivedData/coreader-intent CODE_SIGNING_ALLOWED=NO test
./scripts/run_app_macos.sh --app-path build/DerivedData/coreader-intent/Build/Products/Debug/CoReader.app --background
```

Replace `coreader-intent` with your `AGENT_NAME` (`scripts/xcbuild.sh` requires
one). Definition of done: `swift test` and the `xcbuild.sh --action test` line
both exit 0. Run the GUI only via `run_app_macos.sh` on that Debug `.app`.

## Guardrails

- Destination is `platform=macOS`. After adding a Swift file under
  `Sources/CoReaderApp/` or `Tests/CoReaderAppTests/`, rerun
  `xcodegen generate --spec project.yml` so the Xcode target lists it.
- Keep `Package.swift` and `project.yml` version/deployment fields in
  agreement when you bump them (`SWIFT_VERSION` vs `swift-tools-version`,
  macOS 15).
- Tests are Swift Testing (`import Testing`, `@Test`), e.g.
  `Tests/CoReaderAppTests/AppModelReaderStateTests.swift`.
- Orchestration lives in `Sources/CoReaderApp/App/AppModel.swift`. Views
  under `Features/` call that model; they do not open SQLite, PDF streams,
  or HTTP themselves.
- Local providers only (Ollama, Claude CLI in `AIProviderKind`). Keep
  `project.yml` `platform: macOS`.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
