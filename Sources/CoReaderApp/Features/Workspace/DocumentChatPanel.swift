import Observation
import SwiftUI

struct DocumentChatPanel: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ask the Reader")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ReaderTheme.ink)

                Text("Choose a grounded scope before you ask: selection, current focus, or a document sweep.")
                    .font(.subheadline)
                    .foregroundStyle(ReaderTheme.slate)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LearningAction.allCases) { action in
                        Button(action.title, systemImage: action.systemImage) {
                            Task {
                                await appModel.runQuickAction(action)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(ReaderTheme.teal)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ReaderTheme.slate)

                HStack(spacing: 8) {
                    ForEach(DocumentQueryScope.allCases) { scope in
                        scopeButton(scope)
                    }
                }

                Text(appModel.effectiveQueryScope.detail)
                    .font(.caption)
                    .foregroundStyle(ReaderTheme.slate)
            }

            if appModel.chatTranscript.isEmpty {
                ContentUnavailableView(
                    "No AI thread yet",
                    systemImage: "text.bubble",
                    description: Text("Select text or stay on the current page, then ask a grounded question.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(appModel.chatTranscript) { message in
                            ChatMessageBubble(message: message)
                        }
                    }
                }
            }

            if let chatError = appModel.chatError {
                Text(chatError)
                    .font(.caption)
                    .foregroundStyle(ReaderTheme.rose)
            }

            TextField("Ask about the current selection or visible section", text: $appModel.chatInput, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...)

            Button("Ask", systemImage: "sparkles") {
                Task {
                    await appModel.askQuestion()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(ReaderTheme.teal)
            .disabled(!appModel.canSubmitQuestion)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func scopeButton(_ scope: DocumentQueryScope) -> some View {
        let isDisabled = scope == .selection && !appModel.hasActiveSelection
        let isSelected = appModel.effectiveQueryScope == scope && !isDisabled

        return Button(scope.title) {
            appModel.setQueryScope(scope)
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.semibold))
        .foregroundStyle(isSelected ? Color.white : isDisabled ? ReaderTheme.slate.opacity(0.55) : ReaderTheme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? ReaderTheme.teal : ReaderTheme.chromeStrong.opacity(0.45), in: Capsule())
        .overlay(
            Capsule()
                .stroke(isSelected ? ReaderTheme.teal : ReaderTheme.chromeStrong.opacity(0.8), lineWidth: 1)
        )
        .disabled(isDisabled)
    }
}
