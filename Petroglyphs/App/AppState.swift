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

    init() {
        if let data = UserDefaults.standard.data(forKey: "selectedCodexChat") {
            selectedCodexChat = try? JSONDecoder().decode(CodexChatTarget.self, from: data)
        }
    }
}
