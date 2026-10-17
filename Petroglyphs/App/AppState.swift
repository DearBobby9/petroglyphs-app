import SwiftUI

enum AppPage {
    case landing
    case canvas
}

@Observable
@MainActor
class AppState {
    let canvasViewModel = CanvasViewModel()
    private(set) var creationDrafts: [CodexCreationDraftSummary] = []
    var currentPage: AppPage = .landing
    private let recentChatStore = CodexRecentChatStore()
    private let targetAvailability = CodexTargetAvailabilityModel()
    private var selectedTargetGeneration = UUID()
    var targetError: String? { targetAvailability.matches(selectedCodexChat) ? targetAvailability.error : nil }
    var isCheckingTarget: Bool { targetAvailability.matches(selectedCodexChat) && targetAvailability.isLoading }
    var canSendToSelectedTarget: Bool { selectedCodexChat?.host.canSelect == true && targetError == nil }
    var recentCodexChats: [CodexChatTarget] { recentChatStore.targets }
    var selectedCodexChat: CodexChatTarget? {
        didSet {
            selectedTargetGeneration = UUID()
            if let selectedCodexChat, let data = try? JSONEncoder().encode(selectedCodexChat) {
                UserDefaults.standard.set(data, forKey: "selectedCodexChat")
                recentChatStore.remember(selectedCodexChat)
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedCodexChat")
            }
        }
    }
    let codexConversation = CodexConversationStore()
    var newCodexChat: CodexProjectCreationModel? {
        didSet {
            if let draft = newCodexChat,
               let data = try? JSONEncoder().encode(CodexNewChatDestination(serverURL: draft.serverURL, host: draft.host, project: draft.project, draftID: draft.draftID)) {
                UserDefaults.standard.set(data, forKey: "newCodexChatDestination")
            } else {
                UserDefaults.standard.removeObject(forKey: "newCodexChatDestination")
            }
            refreshCreationDrafts()
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "selectedCodexChat") {
            selectedCodexChat = try? JSONDecoder().decode(CodexChatTarget.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: "newCodexChatDestination"),
           let destination = try? JSONDecoder().decode(CodexNewChatDestination.self, from: data) {
            newCodexChat = CodexProjectCreationModel(project: destination.project, host: destination.host, serverURL: destination.serverURL, draftID: destination.draftID)
        }
        if let selectedCodexChat { recentChatStore.remember(selectedCodexChat) }
        refreshCreationDrafts()
    }

    func restoreTarget(for serverURL: URL?) {
        if selectedCodexChat?.serverURL != serverURL {
            selectedCodexChat = serverURL.flatMap { recentChatStore.latest(for: $0) }
        }
        if newCodexChat?.serverURL != serverURL { newCodexChat = nil }
    }

    func refreshSelectedTarget() async {
        guard let original = selectedCodexChat else { return }
        let generation = selectedTargetGeneration
        let refreshed = await targetAvailability.refresh(for: original)
        guard selectedTargetGeneration == generation else { return }
        if let refreshed { selectedCodexChat = refreshed }
    }

    func refreshCreationDrafts() { creationDrafts = CodexProjectCreationModel.savedDrafts() }

    func resumeCreationDraft(_ summary: CodexCreationDraftSummary) {
        guard let destination = summary.destination, summary.recoveryError == nil else { return }
        newCodexChat = CodexProjectCreationModel(project: destination.project, host: destination.host,
            serverURL: destination.serverURL, draftID: summary.id)
    }

    func startNewChat(project: CodexProject, host: CodexHost, serverURL: URL) {
        if let draft = newCodexChat, draft.request == nil {
            if draft.changeDestination(project: project, host: host, serverURL: serverURL) { newCodexChat = draft }
        } else {
            startIndependentChat(project: project, host: host, serverURL: serverURL)
        }
    }

    func startIndependentChat(project: CodexProject, host: CodexHost, serverURL: URL) {
        newCodexChat = CodexProjectCreationModel(project: project, host: host, serverURL: serverURL, draftID: UUID().uuidString.lowercased())
    }

    func finishNewChat(_ thread: CodexThread, from draft: CodexProjectCreationModel) {
        guard newCodexChat === draft else { return }
        let target = CodexChatTarget(thread: thread, serverURL: draft.serverURL, host: draft.host,
                                     projectId: draft.project.id, projectName: draft.project.displayName)
        guard let request = draft.request, let receipt = draft.receipt else { return }
        do {
            try codexConversation.handoffCreation(request, receipt: receipt, to: target)
        } catch {
            draft.reportHandoffFailure(error)
            return
        }
        selectedCodexChat = target
        // Destination persistence is the handoff boundary. Repeating this operation
        // after a crash reuses the creation ID and cannot duplicate its first message.
        if receipt.firstMessageRequestId == nil, receipt.firstMessageState != "not_sent", receipt.state != .completed {
            // Older bridges have no first-message receipt endpoint. Keep the original
            // creation record available for status checks after opening its chat.
            newCodexChat = nil
            return
        }
        guard draft.acknowledgeOpenedChat() else { refreshCreationDrafts(); return }
        newCodexChat = nil
    }
}
