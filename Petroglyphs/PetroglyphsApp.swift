import SwiftUI

@main
struct PetroglyphsApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("serverURLString") private var serverURLString = ""
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    @State private var appState = AppState()
    @State private var connectionMonitor = ConnectionMonitor()
    @State private var discovery = BridgeDiscoveryModel()

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
            .environment(discovery)
            .preferredColorScheme(darkModeEnabled ? .dark : .light)
            .onChange(of: scenePhase) { _, phase in
                connectionMonitor.setForeground(phase == .active)
                discovery.setForeground(phase == .active)
                if phase != .active { appState.canvasViewModel.save() }
            }
            .task {
                discovery.setForeground(true)
                guard connectionMonitor.serverURL == nil else { return }
                let savedURL = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !savedURL.isEmpty else { return }
                let rawURL = savedURL.hasPrefix("http") ? savedURL : "http://\(savedURL)"
                guard let url = URL(string: rawURL), url.host != nil else { return }
                connectionMonitor.start(url: url)
            }
            .onChange(of: connectionMonitor.serverURL) { _, url in
                appState.restoreTarget(for: url)
            }
            .onChange(of: discovery.connectionRevision) { _, _ in
                if let url = discovery.pairedURL { connectionMonitor.start(url: url) }
            }
        }
    }
}
