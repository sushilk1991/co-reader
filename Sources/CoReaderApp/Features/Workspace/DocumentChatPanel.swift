import Observation
import SwiftUI

struct DocumentChatPanel: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ask the Document")
                    .font(.title3.weight(.semibold))

                Text("Use local models to interrogate the current document, extract code, or clarify dense sections.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if appModel.chatTranscript.isEmpty {
                ContentUnavailableView(
                    "No questions yet",
                    systemImage: "text.bubble",
                    description: Text("Select a document and ask a focused question to start building context.")
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
                    .foregroundStyle(.red)
            }

            TextField("Ask about the current document", text: $appModel.chatInput, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...)

            Button("Ask", systemImage: "sparkles") {
                Task {
                    await appModel.askQuestion()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!appModel.canSubmitQuestion)
        }
        .padding(20)
        .frame(width: 360)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.16), in: RoundedRectangle(cornerRadius: 22))
    }
}
