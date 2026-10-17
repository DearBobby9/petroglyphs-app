import SwiftUI

struct CodexConversationTurn: Identifiable {
    let id: String
    var messages: [CodexConversationMessage]

    static func group(_ messages: [CodexConversationMessage]) -> [CodexConversationTurn] {
        InteractionDiagnostics.shared.record(.chatTurnGroupingBegin)
        defer { InteractionDiagnostics.shared.record(.chatTurnGroupingEnd) }
        var turns: [CodexConversationTurn] = []
        for message in messages {
            let id = message.turnId.map { "turn:\($0)" } ?? message.displayID
            if turns.last?.id == id { turns[turns.count - 1].messages.append(message) }
            else { turns.append(CodexConversationTurn(id: id, messages: [message])) }
        }
        return turns
    }
}

struct CodexConversationTurnView: View {
    let turn: CodexConversationTurn
    let target: CodexChatTarget
    let store: CodexConversationStore
    @State private var processExpanded = false

    private var progress: [CodexConversationMessage] {
        turn.messages.filter { $0.role != "user" && $0.phase == "commentary" && $0.state != .failed }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(turn.messages.filter { $0.role == "user" }, id: \.displayID) { row($0) }
            if !progress.isEmpty {
                DisclosureGroup(isExpanded: $processExpanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(progress, id: \.displayID) { row($0) }
                    }.padding(.top, 8)
                } label: {
                    Label("Process · \(progress.count)", systemImage: "list.bullet.rectangle")
                        .font(.caption.weight(.semibold))
                }
                .tint(Color.charcoal)
                .accessibilityIdentifier("chat.process.\(turn.id)")
            }
            ForEach(turn.messages.filter { $0.role != "user" && ($0.phase != "commentary" || $0.state == .failed) }, id: \.displayID) { row($0) }
            if turn.messages.contains(where: { $0.role != "user" && $0.state == .failed }) {
                Label("Task failed", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Color.rust)
            } else if turn.messages.contains(where: { $0.role != "user" && ($0.phase == "final_answer" || $0.phase == "final") && $0.state == .completed }) {
                Label("Completed", systemImage: "checkmark.circle").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            let readingID = store.session(for: target).readingMessageID
            if progress.contains(where: { $0.displayID == readingID }) { processExpanded = true }
        }
    }

    private func row(_ message: CodexConversationMessage) -> some View {
        CodexMessageRow(message: message, target: target, store: store)
            .id(message.displayID)
            .background(GeometryReader { geometry in
                Color.clear.preference(key: MessagePositionKey.self,
                                       value: [message.displayID: geometry.frame(in: .named("conversation-scroll"))])
            })
    }
}
