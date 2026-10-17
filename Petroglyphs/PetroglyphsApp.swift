import SwiftUI

@main
struct PetroglyphsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("serverURLString") private var serverURLString = ""
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    @State private var appState = AppState()
    @State private var connectionMonitor = ConnectionMonitor()

    var body: some Scene {
        WindowGroup {
            Group {
                switch appState.currentPage {
                case .landing:
                    LandingView()
                case .canvas:
                    CanvasPageView()
                }
            }
            .environment(appState)
            .environment(connectionMonitor)
            .preferredColorScheme(darkModeEnabled ? .dark : .light)
            .onChange(of: scenePhase) { _, phase in
                connectionMonitor.setForeground(phase == .active)
                if phase != .active { appState.canvasViewModel.save() }
            }
            .task {
                guard connectionMonitor.serverURL == nil else { return }
                let savedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !savedURL.isEmpty else { return }
                let rawURL = savedURL.hasPrefix("http") ? savedURL : "http://\(savedURL)"
                guard let url = URL(string: rawURL), url.host != nil else { return }
                connectionMonitor.start(url: url)
            }
        }
    }
}
