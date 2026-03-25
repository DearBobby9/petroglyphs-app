import SwiftUI
import PencilKit

struct CanvasPageView: View {
    @Environment(AppState.self) var appState
    @Environment(ConnectionMonitor.self) var connectionMonitor
    @State private var vm = CanvasViewModel()
    private let network = NetworkService()
    @State private var offlineQueue = OfflineQueue()

    var body: some View {
        ZStack {
            Color.limestone.ignoresSafeArea()

            HStack(spacing: 0) {
                // Canvas area
                ZStack {
                    // Stone border frame
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.clay.opacity(0.4))
                        .padding(4)

                    CanvasView(drawing: $vm.drawing, onFirstStroke: vm.onFirstStroke)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(8)

                    // Clear gesture detector
                    ClearGestureView { vm.clear(); triggerClearHaptic() }

                    // Overlays
                    WipeAnimationOverlay(isShowing: $vm.showWipeAnimation)
                    CastSuccessOverlay(isShowing: $vm.showCastSuccess)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 8)

                // Send button
                VStack {
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
                    Spacer()
                }
                .padding(.trailing, 16)
            }

            // Top-left controls
            VStack {
                HStack {
                    Button {
                        appState.currentPage = .landing
                    } label: {
                        Image(systemName: "house")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.charcoal.opacity(0.7))
                            .padding(10)
                            .background(Color.sandstone.opacity(0.8))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    ConnectionDot(isConnected: connectionMonitor.isConnected)
                        .padding(.leading, 4)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                Spacer()
            }
        }
        .onChange(of: connectionMonitor.isConnected) { _, isConnected in
            if isConnected, let url = connectionMonitor.serverURL {
                offlineQueue.drain(to: url)
            }
        }
    }

    private func castCurrent() {
        vm.cast(combo: nil, networkService: network, offlineQueue: offlineQueue, isConnected: connectionMonitor.isConnected)
        triggerCastHaptic()
    }
}

// MARK: - Three-finger + palm swipe gesture

struct ClearGestureView: UIViewRepresentable {
    let onClear: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let threeFingerSwipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe))
        threeFingerSwipe.numberOfTouchesRequired = 3
        threeFingerSwipe.direction = .left
        view.addGestureRecognizer(threeFingerSwipe)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onClear: onClear) }

    class Coordinator: NSObject {
        let onClear: () -> Void
        init(onClear: @escaping () -> Void) { self.onClear = onClear }

        @objc func handleSwipe() { onClear() }
    }
}
