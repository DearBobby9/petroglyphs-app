import SwiftUI
import PencilKit

struct CanvasPageView: View {
    @Environment(AppState.self) var appState
    @Environment(ConnectionMonitor.self) var connectionMonitor
    @AppStorage("pairingCode") private var pairingCode: String = ""
    @AppStorage("hasSeenClearHint") private var hasSeenClearHint: Bool = false
    @State private var vm = CanvasViewModel()
    @State private var showClearHint = false
    private let network = NetworkService()
    @State private var offlineQueue = OfflineQueue()

    var body: some View {
        ZStack {
            Color.limestone.ignoresSafeArea()

            // Canvas takes full width, symmetric padding
            ZStack {
                CanvasView(drawing: $vm.drawing, onFirstStroke: vm.onFirstStroke, onClear: {
                    vm.clear()
                    triggerClearHaptic()
                    hasSeenClearHint = true
                    showClearHint = false
                })
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                // Overlays
                WipeAnimationOverlay(isShowing: $vm.showWipeAnimation)
                CastSuccessOverlay(isShowing: $vm.showCastSuccess)
                if showClearHint {
                    SwipeToClearHint(isShowing: $showClearHint)
                        .onChange(of: showClearHint) { _, showing in
                            if !showing { hasSeenClearHint = true }
                        }
                }

                // Home button + connection dot (top-leading)
                VStack {
                    HStack(spacing: 6) {
                        Button {
                            appState.currentPage = .landing
                        } label: {
                            Image(systemName: "house")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.charcoal.opacity(0.6))
                                .padding(8)
                                .background(Color.sandstone.opacity(0.7))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        ConnectionDot(isConnected: connectionMonitor.isConnected)
                        Spacer()
                    }
                    .padding(.leading, 16)
                    .padding(.top, 16)
                    Spacer()
                }

                // Send button (middle-right, on canvas)
                HStack {
                    Spacer()
                    Button(action: castCurrent) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(Color.white)
                            .frame(width: 56, height: 56)
                            .background(Color.ochre)
                            .clipShape(Circle())
                            .shadow(color: Color.charcoal.opacity(0.15), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isCasting)
                    .opacity(vm.isCasting ? 0.5 : 1.0)
                    .padding(.trailing, 16)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
        }
        .onAppear {
            if !hasSeenClearHint {
                showClearHint = true
            }
        }
        .onChange(of: connectionMonitor.isConnected) { _, isConnected in
            if isConnected, let url = connectionMonitor.serverURL {
                offlineQueue.drain(to: url)
            }
        }
    }

    private func castCurrent() {
        vm.cast(
            combo: nil,
            networkService: network,
            offlineQueue: offlineQueue,
            serverURL: connectionMonitor.serverURL,
            isConnected: connectionMonitor.isConnected,
            pairingCode: pairingCode
        )
        triggerCastHaptic()
    }
}

