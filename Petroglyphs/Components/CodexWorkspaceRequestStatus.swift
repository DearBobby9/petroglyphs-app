import SwiftUI

struct CodexWorkspaceRequestStatus: View {
    @Environment(\.scenePhase) private var scenePhase
    let reference: CodexSubmissionReference
    let store: CodexConversationStore
    let onOpen: () -> Void

    private var state: CodexMessageState? {
        store.receipt(reference.id, for: reference.target)?.state ?? store.localMessage(reference.id, for: reference.target)?.state
    }

    private var status: String {
        switch state {
        case .pending: return "Waiting in bridge queue"
        case .dispatching: return "Dispatching"
        case .queued: return "Queued in Codex"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .unknown: return "Delivery not confirmed"
        case .cancelled: return "Cancelled before dispatch"
        case nil: return "Open original request to check status"
        }
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: state == .unknown || state == .failed ? "exclamationmark.bubble" : "bubble.left.and.bubble.right")
                VStack(alignment: .leading, spacing: 3) {
                    Text(status).font(.callout.weight(.semibold))
                    Text("\(reference.target.host.name) · \(reference.target.thread.displayTitle)")
                        .font(.caption).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.right")
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .foregroundStyle(state == .unknown || state == .failed ? Color.rust : Color.charcoal)
            .background(Color.panelBackground, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the saved original message without sending again.")
        .accessibilityIdentifier("canvas.request.\(reference.id)")
        .task(id: ObservationRequest(key: CodexConversationKey(reference.target), isActive: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            await store.observe(target: reference.target)
        }
    }

    private struct ObservationRequest: Equatable {
        let key: CodexConversationKey
        let isActive: Bool
    }
}
