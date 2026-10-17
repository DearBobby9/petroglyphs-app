import SwiftUI

struct DiscoveredMacsView: View {
    @Environment(BridgeDiscoveryModel.self) private var discovery
    @Environment(ConnectionMonitor.self) private var connectionMonitor
    @State private var candidate: DiscoveredBridge?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Available Macs").font(.headline)
                Spacer()
                if discovery.isSearching { ProgressView().controlSize(.small) }
                Button { Task { await discovery.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Refresh Mac discovery")
            }
            Text(discovery.discoveryStatus)
                .font(.footnote).foregroundStyle(.secondary)
                .accessibilityIdentifier("discovery.status")
            ForEach(discovery.bridges) { bridge in
                let connected = connectionMonitor.isConnected && connectionMonitor.serverURL.flatMap(PairedBridge.init)?.identity == bridge.id
                let saved = discovery.isPaired(bridge)
                Button {
                    if saved { Task { await discovery.connect(to: bridge) } }
                    else { candidate = bridge }
                } label: {
                    HStack {
                        Image(systemName: "desktopcomputer")
                        VStack(alignment: .leading, spacing: 3) {
                            Text(bridge.name).font(.body.weight(.medium))
                            Text(bridge.route == .tailscale ? "Tailscale" : "Nearby")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(connected ? "Connected" : (saved ? "Connect" : "Pair"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(discovery.pairingBridge != nil)
                .accessibilityIdentifier("discovery.mac.\(bridge.id)")
            }
            if let bridge = discovery.pairingBridge {
                Divider()
                Text(discovery.isPaired(bridge) ? "Connect to \(bridge.name)" : "Pair with \(bridge.name)").font(.subheadline.bold())
                if let code = discovery.pairingCode {
                    Text(code).font(.system(.largeTitle, design: .monospaced).bold())
                        .textSelection(.enabled).accessibilityIdentifier("pairing.code")
                }
                if let status = discovery.pairingStatus { Text(status).font(.footnote) }
                Button(discovery.isPaired(bridge) ? "Cancel connection" : "Cancel pairing", role: .cancel) { discovery.cancelPairing() }
                    .frame(minHeight: 44)
            } else if let status = discovery.pairingStatus {
                Text(status).font(.footnote).foregroundStyle(Color.moss)
            }
            if let error = discovery.error {
                Text(error).font(.footnote).foregroundStyle(Color.rust)
                    .accessibilityIdentifier("pairing.error")
                Button("Dismiss") { discovery.cancelPairing() }.frame(minHeight: 44)
            }
        }
        .confirmationDialog("Pair with \(candidate?.name ?? "Mac")?", isPresented: Binding(
            get: { candidate != nil }, set: { if !$0 { candidate = nil } }
        ), titleVisibility: .visible) {
            if let candidate {
                Button("Request wireless pairing") { discovery.pair(with: candidate); self.candidate = nil }
            }
            Button("Cancel", role: .cancel) { candidate = nil }
        } message: {
            Text("Confirm the matching code in the approval window on your Mac. A cable, address and port are not required.")
        }
    }
}
