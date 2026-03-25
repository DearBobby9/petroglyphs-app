import SwiftUI

@main
struct PetroglyphsApp: App {
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
        }
    }
}
