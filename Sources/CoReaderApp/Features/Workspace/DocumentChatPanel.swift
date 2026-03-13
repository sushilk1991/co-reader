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

                Text("Use the current selection or visible pages, not the whole book blob.")
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
}
