import Observation
import SwiftUI

struct DocumentChatPanel: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ask the Reader")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ReaderTheme.ink)

                Text("Choose a grounded scope before you ask: selection, current focus, or a document sweep.")
                    .font(.subheadline)
                    .foregroundStyle(ReaderTheme.smoke)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LearningAction.allCases) { action in
                        Button {
                            Task {
                                await appModel.runQuickAction(action)
                            }
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ReaderTheme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(ReaderTheme.paper.opacity(0.92), in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(ReaderTheme.lineSoft, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Scope")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ReaderTheme.smoke)

                HStack(spacing: 8) {
                    ForEach(DocumentQueryScope.allCases) { scope in
                        scopeButton(scope)
                    }
                }

                Text(appModel.effectiveQueryScope.detail)
                    .font(.caption)
                    .foregroundStyle(ReaderTheme.smoke)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(ReaderTheme.panelRaised.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Group {
                if appModel.chatTranscript.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(ReaderTheme.smoke)
                            .padding(14)
                            .background(ReaderTheme.paper, in: Circle())

                        Text("No AI thread yet")
                            .font(.headline)
                            .foregroundStyle(ReaderTheme.ink)

                        Text("Select text or stay on the current page, then ask a grounded question.")
                            .font(.subheadline)
                            .foregroundStyle(ReaderTheme.smoke)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 240)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(appModel.chatTranscript) { message in
                                ChatMessageBubble(message: message)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ReaderTheme.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(ReaderTheme.lineSoft, lineWidth: 1)
            )

            if let chatError = appModel.chatError {
                Text(chatError)
                    .font(.caption)
                    .foregroundStyle(ReaderTheme.rose)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ReaderTheme.roseSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            TextField("Ask about the current selection or visible section", text: $appModel.chatInput, axis: .vertical)
                .lineLimit(3...)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(ReaderTheme.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(ReaderTheme.lineSoft, lineWidth: 1)
                )

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
        .background(isSelected ? ReaderTheme.teal : ReaderTheme.paper.opacity(0.92), in: Capsule())
        .overlay(
            Capsule()
                .stroke(isSelected ? ReaderTheme.teal : ReaderTheme.lineSoft, lineWidth: 1)
        )
        .disabled(isDisabled)
    }
}
