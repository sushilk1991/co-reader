# Co-Reader Core Architecture Design

**Context**

`co-reader` is a new macOS desktop app for accelerated reading of PDFs, EPUBs, and imported web content. The first implementation pass should optimize for a native macOS experience, strong local-first behavior, and a modular AI integration layer that can work without cloud services.

**Goals**

- Ship a native-feeling macOS reader shell in SwiftUI.
- Support local AI integrations through Ollama and the local `claude` CLI.
- Persist reading artifacts in two places:
  - portable Markdown notes on disk
  - a local SQLite index for fast search and metadata queries
- Keep the architecture small enough to iterate in frequent, verified commits.

**Non-Goals For The First Iteration**

- Full EPUB rendering fidelity.
- Remote sync.
- Complex multi-window coordination.
- General-purpose plugin infrastructure.

**Architecture**

The app will be a Swift package that runs a SwiftUI macOS app entry point. This avoids waiting on XcodeGen while preserving a clean structure that can later be adopted into an `.xcodeproj` if needed. The package will be split by responsibility:

- `App`: application bootstrapping and top-level dependency container.
- `Features`: user-facing screens and view models.
- `Core/AI`: provider discovery and local AI execution adapters.
- `Core/Knowledge`: Markdown note persistence and SQLite-backed indexing.

This structure keeps reader features independent from persistence and model execution, so later additions like document Q&A, image explanation, or summarization can depend on the same local service interfaces.

**Data Flow**

The top-level app model owns service instances and exposes observable state to SwiftUI. Feature view models call protocol-backed services instead of shelling out or hitting HTTP directly. The first feature flow is:

1. App launches.
2. Provider discovery checks for Ollama at `http://127.0.0.1:11434` and for a `claude` executable on `PATH`.
3. Results are normalized into a unified provider status model.
4. SwiftUI renders the availability and detected models.

The second feature flow is:

1. Reading-related events create note payloads.
2. A knowledge store writes Markdown files into a local notes directory.
3. The same note metadata is indexed in SQLite for instant filtering and search.

**Error Handling**

- Discovery failures are non-fatal and render as unavailable providers with diagnostic messages.
- Markdown persistence errors surface as thrown Swift errors and are testable independently.
- SQLite setup is idempotent and should create schema on first use.
- External integrations are always wrapped by protocols so tests can simulate failures without real network or subprocesses.

**Testing Strategy**

- Use strict TDD for each feature.
- Unit-test provider discovery with injected HTTP and process abstractions.
- Unit-test dual-storage note persistence with temporary directories and databases.
- Run `swift test` before every completion claim and every checkpoint commit.

**Initial Milestones**

1. Scaffold the macOS SwiftUI app package and baseline test target.
2. Ship provider discovery for Ollama and Claude CLI.
3. Ship Markdown + SQLite note persistence.
4. Add document import and reading surfaces on top of the stabilized core.
