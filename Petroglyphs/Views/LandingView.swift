import SwiftUI

struct LandingView: View {
    @Environment(AppState.self) var appState
    @Environment(ConnectionMonitor.self) var connectionMonitor
    @State private var showServer = false
    @State private var showSettings = false

    var body: some View {
        ZStack {
            SandstoneBackground()

            VStack(spacing: 0) {
                Spacer()

                // Title
                VStack(spacing: 10) {
                    Text("Petroglyphs ")
                        .font(.caveat(60, weight: .bold))
                        .foregroundStyle(Color.charcoal)
                        .fixedSize(horizontal: true, vertical: false)
                    Text("A handwriting keyboard for AI")
                        .font(.rounded(18))
                        .foregroundStyle(Color.charcoal.opacity(0.6))
                }

                Spacer()

                // Connection status
                HStack(spacing: 8) {
                    ConnectionDot(isConnected: connectionMonitor.isConnected)
                    Text(connectionMonitor.isConnected ? "Connected to server" : "No server connection")
                        .font(.rounded(14))
                        .foregroundStyle(Color.charcoal.opacity(0.55))
                }
                .padding(.bottom, 28)

                // Enter button
                OchreButton("Enter") {
                    appState.currentPage = .canvas
                }
                .frame(width: 200)
                .padding(.bottom, 40)

                // Setting tiles
                HStack(spacing: 16) {
                    SettingTile(icon: "network", label: "Server") {
                        showServer = true
                    }
                    SettingTile(icon: "gearshape.fill", label: "Settings") {
                        showSettings = true
                    }
                }
                .padding(.bottom, 48)

                // Footer
                Text("v0.1.0  ·  MIT License  ·  petroglyphs")
                    .font(.rounded(12))
                    .foregroundStyle(Color.charcoal.opacity(0.35))

                Spacer(minLength: 24)
            }
        }
        .sheet(isPresented: $showServer) { ServerSettingsSheet() }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
    }
}
