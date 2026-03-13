import Foundation

struct ChatMessage: Equatable, Identifiable, Sendable {
    let id: UUID
    let role: ChatRole
    let content: String

    init(id: UUID = UUID(), role: ChatRole, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}
