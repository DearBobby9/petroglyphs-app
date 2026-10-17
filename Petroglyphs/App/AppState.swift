import SwiftUI

enum AppPage {
    case landing
    case canvas
}

@Observable
@MainActor
class AppState {
    var currentPage: AppPage = .landing
    var selectedCodexChat: CodexChatTarget? {
        didSet {
            if let selectedCodexChat, let data = try? JSONEncoder().encode(selectedCodexChat) {
                UserDefaults.standard.set(data, forKey: "selectedCodexChat")
            } else {
                UserDefaults.standard.removeObject(forKey: "selectedCodexChat")
            }
        }
    }
    let codexConversation = CodexConversationStore()
    var newCodexChat: CodexProjectCreationModel? {
        didSet {
            if let draft = newCodexChat,
               let data = try? JSONEncoder().encode(CodexNewChatDestination(serverURL: draft.serverURL, host: draft.host, project: draft.project)) {
                UserDefaults.standard.set(data, forKey: "newCodexChatDestination")
            } else {
                UserDefaults.standard.removeObject(forKey: "newCodexChatDestination")
            }
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "selectedCodexChat") {
            selectedCodexChat = try? JSONDecoder().decode(CodexChatTarget.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: "newCodexChatDestination"),
           let destination = try? JSONDecoder().decode(CodexNewChatDestination.self, from: data) {
            newCodexChat = CodexProjectCreationModel(project: destination.project, host: destination.host, serverURL: destination.serverURL)
        }
    }

    func startNewChat(project: CodexProject, host: CodexHost, serverURL: URL) {
        newCodexChat = CodexProjectCreationModel(project: project, host: host, serverURL: serverURL)
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
