import SwiftUI
import UIKit

struct CodexExecutionControlsView: View {
    let target: CodexChatTarget
    let runState: String
    let latestTurnID: String?
    @State private var model = CodexExecutionControlModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let result = model.stopResult {
                Label(result.status == "already_finished" ? "This turn already finished" : "Stop confirmed", systemImage: "checkmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.canStop || model.isStopping {
                Button(model.isStopping ? "Stopping this turn…" : "Stop this turn", systemImage: "stop.circle") {
                    Task { await model.stop() }
                }
                .disabled(!model.canStop)
                .frame(minHeight: 44)
                .accessibilityHint("Stops the verified active turn on \(target.host.name).")
                .accessibilityIdentifier("chat.stopTurn")
            }
            if runState == "waiting" {
                if let interactions = model.controls?.pendingInteractions, !interactions.isEmpty {
                    ForEach(interactions) { interaction in
                        Label(interaction.reason, systemImage: "person.crop.circle.badge.questionmark")
                            .font(.caption).foregroundStyle(Color.rust)
                    }
                } else {
                    Text("The waiting reason is not available from this bridge.").font(.caption).foregroundStyle(.secondary)
                }
                Text("Handle answers or approvals in this chat in Codex in ChatGPT Desktop on \(target.host.name).")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Copy chat ID") { UIPasteboard.general.string = target.thread.id }
                    .font(.caption).frame(minHeight: 44)
            }
            if runState == "running", let capability = model.controls?.capabilities.stop, !capability.supported {
                Text("\(capability.reason ?? "Stopping this turn is not supported by this bridge.") Use Codex in ChatGPT Desktop on \(target.host.name).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.error {
                Text(error).font(.caption).foregroundStyle(Color.rust).textSelection(.enabled)
            }
            if runState == "waiting" || model.error != nil {
                Button("Refresh controls") { Task { await model.load(for: target) } }
                    .font(.caption).frame(minHeight: 44).disabled(model.isLoading || model.isStopping)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: "\(CodexConversationKey(target).storageID):\(runState):\(latestTurnID ?? "")") {
            await model.load(for: target)
        }
        .accessibilityIdentifier("chat.executionControls")
    }
}
