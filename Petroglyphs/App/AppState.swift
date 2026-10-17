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
    var recentCodexChats: [CodexChatTarget] { recentChatStore.targets }
    var selectedCodexChat: CodexChatTarget? {
        didSet {
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
        if let selection = draft.request?.selection {
            codexConversation.setDraftModelSelection(CodexDraftModelSelection(model: selection.model, reasoningEffort: selection.reasoningEffort), for: target)
        }
        selectedCodexChat = target
        draft.acknowledgeOpenedChat()
        newCodexChat = nil
    }
}
