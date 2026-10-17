import SwiftUI

struct LandingView: View {
    @Environment(AppState.self) var appState
    @Environment(ConnectionMonitor.self) var connectionMonitor
    @Environment(BridgeDiscoveryModel.self) private var discovery
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
                    Text("Draw, discuss, and build with Codex")
                        .font(.rounded(18))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Connection status
                HStack(spacing: 8) {
                    ConnectionDot(isConnected: connectionMonitor.isConnected)
                    Text(connectionMonitor.statusDescription)
                        .font(.rounded(14))
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 28)

                if !connectionMonitor.isConnected || discovery.pairingBridge != nil {
                    ScrollView {
                        DiscoveredMacsView().padding(16)
                    }
                    .frame(maxWidth: 480, maxHeight: 240)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 24).padding(.bottom, 20)
                }

                // Enter button
                OchreButton(connectionMonitor.isConnected ? "Open workspace" : "Connect to Mac") {
                    if connectionMonitor.isConnected { appState.currentPage = .canvas }
                    else { showServer = true }
                }
                .frame(width: 200)
                .padding(.bottom, 40)

                if !connectionMonitor.isConnected {
                    Button("Open saved workspace") { appState.currentPage = .canvas }
                        .frame(minHeight: 44).padding(.bottom, 16)
                }

                // Setting tiles
                HStack(spacing: 16) {
                    SettingTile(icon: "network", label: "Connection") {
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
                    .foregroundStyle(.secondary)

                Spacer(minLength: 24)
            }
        }
        .sheet(isPresented: $showServer) { ServerSettingsSheet() }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
    }
}
