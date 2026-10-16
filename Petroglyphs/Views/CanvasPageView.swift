import SwiftUI
import PencilKit

struct CanvasPageView: View {
    @Environment(AppState.self) var appState
    @Environment(ConnectionMonitor.self) var connectionMonitor
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("pairingCode") private var pairingCode: String = ""
    @AppStorage("hasSeenClearHint") private var hasSeenClearHint: Bool = false
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    @AppStorage("canvasBackgroundHex") private var canvasBackgroundHex = CanvasBackground.white.rawValue
    @AppStorage("darkCanvasBackgroundHex") private var darkCanvasBackgroundHex = CanvasBackground.charcoal.rawValue
    @AppStorage("codexRepliesExpanded") private var repliesExpanded = true
    @AppStorage("codexChatSide") private var chatSideRawValue = CanvasChatSide.right.rawValue
    @AppStorage("codexChatWidthFraction") private var chatWidthFraction = CanvasChatFrames.defaultChatFraction
    @AppStorage("codexCanvasCollapsed") private var chatFocused = false
    @State private var vm = CanvasViewModel()
    @State private var showClearHint = false
    @State private var pickerServer: PickerServer?
    @State private var showBackgroundPicker = false
    @State private var composerFocused = false
    @State private var resizingChatExtent: CGFloat?
    private let network = NetworkService()
    @State private var offlineQueue = OfflineQueue()

    private struct PickerServer: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    private struct ConversationRequest: Equatable {
        let target: CodexChatTarget?
        let isActive: Bool
    }

    private var selectedTarget: CodexChatTarget? {
        guard appState.selectedCodexChat?.serverURL == connectionMonitor.serverURL else { return nil }
        return appState.selectedCodexChat
    }

    private var chatSide: CanvasChatSide { CanvasChatSide(rawValue: chatSideRawValue) ?? .right }

    private var canvasBackground: CanvasBackground {
        let hex = darkModeEnabled ? darkCanvasBackgroundHex : canvasBackgroundHex
        return CanvasBackground(rawValue: hex) ?? (darkModeEnabled ? .charcoal : .white)
    }

    private var hasReplyPanel: Bool {
        connectionMonitor.requiresCodexThread == true || selectedTarget != nil
    }

    private var canSend: Bool {
        guard !vm.isCasting, !vm.drawing.strokes.isEmpty,
              connectionMonitor.serverURL != nil,
              let requiresThread = connectionMonitor.requiresCodexThread else { return false }
        return !requiresThread || (selectedTarget?.host.canSelect == true && connectionMonitor.isConnected)
    }

    private var connectionMessage: String? {
        guard connectionMonitor.serverURL != nil else { return "Connect to a server from the home screen." }
        guard let requiresThread = connectionMonitor.requiresCodexThread else {
            return connectionMonitor.isConnected ? "Checking destination…" : "Waiting for the server connection…"
        }
        if requiresThread && !connectionMonitor.isConnected {
            return "Reconnect to your Mac to send. Your drawing stays here."
        }
        if requiresThread && selectedTarget == nil {
            return "Choose a Codex chat before sending."
        }
        if requiresThread, let reason = selectedTarget?.host.unavailabilityReason {
            return reason
        }
        return nil
    }

    var body: some View {
        @Bindable var appState = appState

        ZStack {
            Color.limestone.ignoresSafeArea()
            GeometryReader { geometry in
                let useSidebar = CanvasChatFrames.supportsSideBySide(in: geometry.size, accessibilityText: dynamicTypeSize.isAccessibilitySize)
                let chatFillsPage = hasReplyPanel && (chatFocused || (composerFocused && !useSidebar))
                let availableSize = CGSize(width: max(0, geometry.size.width - 32), height: max(0, geometry.size.height - 24))
                let stackedChatHeight = CanvasChatFrames.preferredStackedHeight(in: availableSize.height)
                let mode: CanvasChatLayoutMode = !hasReplyPanel ? .canvasOnly : (useSidebar ? .sideBySide : (chatFillsPage ? .chatOnly : .stacked))
                let canResize = hasReplyPanel && useSidebar && repliesExpanded && !chatFillsPage
                let controls = layoutControls(availableWidth: availableSize.width, canResize: canResize)
                let chatExtent = resizingChatExtent ?? (chatFillsPage ? availableSize.width : (repliesExpanded ? CanvasChatFrames.chatExtent(fraction: chatWidthFraction, availableWidth: availableSize.width) : 0))
                CanvasChatLayout(mode: mode, side: chatSide, chatFraction: chatWidthFraction,
                                 isExpanded: repliesExpanded, stackedChatHeight: stackedChatHeight,
                                 chatExtent: chatExtent) {
                    CanvasChatPane(minimumWidth: useSidebar ? CanvasChatFrames.minimumCanvasWidth : 0,
                                   alignment: chatSide == .left ? .trailing : .leading) {
                        drawingSurface
                            .overlay(alignment: chatSide == .left ? .topLeading : .topTrailing) {
                                if hasReplyPanel && useSidebar && !repliesExpanded {
                                    restoreChatControl
                                        .padding(.horizontal, 12)
                                        .padding(.top, 76)
                                }
                            }
                    }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("canvas.surface")
                        .opacity(chatFillsPage && !useSidebar ? 0 : 1)
                        .allowsHitTesting(!chatFillsPage)
                        .accessibilityHidden(chatFillsPage)
                    CanvasChatDivider(controls: controls, availableWidth: availableSize.width,
                                      isEnabled: hasReplyPanel && useSidebar,
                                      onResize: resizeChat,
                                      onResizeEnded: { finishResize(extent: $0, velocity: $1, availableWidth: availableSize.width) },
                                      onResizeCancelled: { withAnimation(layoutAnimation()) { resizingChatExtent = nil } },
                                      onHideChat: toggleReplies,
                                      onHideCanvas: { toggleChatFocus(isFillingPage: false) })
                        .zIndex(1)
                        .allowsHitTesting(hasReplyPanel && useSidebar)
                        .accessibilityHidden(!canResize)
                    if hasReplyPanel {
                        CanvasChatPane(minimumWidth: useSidebar ? CanvasChatFrames.minimumChatWidth : 0,
                                       alignment: chatSide == .left ? .leading : .trailing) {
                            CodexRepliesPanel(
                                store: appState.codexConversation,
                                target: selectedTarget,
                                compactHeight: useSidebar || chatFillsPage ? nil : stackedChatHeight,
                                isExpanded: $repliesExpanded,
                                isFocused: chatFillsPage,
                                canSend: connectionMonitor.isConnected && selectedTarget?.host.canSelect == true,
                                onChooseChat: chooseChat,
                                onAddCanvas: canvasSnapshot,
                                onComposerFocusChanged: { composerFocused = $0 },
                                onExpand: { toggleChatFocus(isFillingPage: chatFillsPage) },
                                layoutControls: controls,
                                keepsContentsMounted: useSidebar,
                                onToggleExpanded: toggleReplies
                            )
                        }
                        .allowsHitTesting(!useSidebar || repliesExpanded)
                        .accessibilityHidden(useSidebar && !repliesExpanded)
                    }
                }
                .coordinateSpace(name: "canvas-chat-workspace")
                .clipped()
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("canvas.workspace")
                .accessibilityValue("Chat on \(chatSide.rawValue), \(chatFillsPage ? "canvas hidden" : (repliesExpanded ? "split" : "chat hidden"))")
                .onChange(of: availableSize.width) { _, _ in resizingChatExtent = nil }
                .onChange(of: useSidebar) { _, _ in resizingChatExtent = nil }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
        }
        .onAppear {
            if !hasSeenClearHint {
                showClearHint = true
            }
        }
        .task(id: ConversationRequest(target: selectedTarget, isActive: scenePhase == .active)) {
            guard scenePhase == .active, let target = selectedTarget else { return }
            await appState.codexConversation.observe(target: target)
        }
        .onChange(of: repliesExpanded) { _, expanded in
            if !expanded {
                dismissComposer()
                chatFocused = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { resizingChatExtent = nil }
        }
        .onChange(of: connectionMonitor.isConnected) { _, isConnected in
            if isConnected, connectionMonitor.requiresCodexThread == false, let url = connectionMonitor.serverURL {
                offlineQueue.drain(to: url)
            }
        }
        .onChange(of: connectionMonitor.serverURL) { _, _ in
            if appState.selectedCodexChat?.serverURL != connectionMonitor.serverURL {
                appState.selectedCodexChat = nil
            }
            pickerServer = nil
        }
        .sheet(item: $pickerServer) { server in
            CodexThreadPickerView(serverURL: server.url, selection: $appState.selectedCodexChat)
                .presentationDetents([.large])
        }
        .alert("Could not send drawing", isPresented: Binding(
            get: { vm.castError != nil },
            set: { if !$0 { vm.castError = nil } }
        )) {
            Button("OK", role: .cancel) { vm.castError = nil }
        } message: {
            Text(vm.castError ?? "")
        }
    }

    private func layoutControls(availableWidth: CGFloat, canResize: Bool) -> CanvasChatLayoutControls {
        let fraction = CanvasChatFrames.chatFraction(chatWidthFraction, availableWidth: availableWidth)
        let narrower = CanvasChatFrames.chatFraction(fraction - 0.05, availableWidth: availableWidth)
        let wider = CanvasChatFrames.chatFraction(fraction + 0.05, availableWidth: availableWidth)
        return CanvasChatLayoutControls(
            side: chatSide, chatFraction: fraction, canResize: canResize,
            canNarrow: narrower < fraction, canWiden: wider > fraction,
            setSide: { resizingChatExtent = nil; chatSideRawValue = $0.rawValue },
            adjustWidth: { amount in
                withAnimation(layoutAnimation()) {
                    chatWidthFraction = CanvasChatFrames.chatFraction(fraction + amount, availableWidth: availableWidth)
                }
            },
            resetWidth: { withAnimation(layoutAnimation()) { chatWidthFraction = CanvasChatFrames.defaultChatFraction } }
        )
    }

    private func resizeChat(to extent: CGFloat) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            resizingChatExtent = extent
            if !repliesExpanded { repliesExpanded = true }
            if chatFocused { chatFocused = false }
        }
    }

    private func finishResize(extent: CGFloat, velocity: CGFloat, availableWidth: CGFloat) {
        let decision = CanvasChatResizeDecision(extent: extent, velocity: velocity, availableWidth: availableWidth)
        let relativeVelocity = abs(decision.extent - extent) > 1 ? Double(velocity / (decision.extent - extent)) : 0
        withAnimation(layoutAnimation(initialVelocity: relativeVelocity)) {
            resizingChatExtent = nil
            switch decision.destination {
            case .hideChat: repliesExpanded = false; chatFocused = false
            case .hideCanvas: repliesExpanded = true; chatFocused = true
            case .split(let fraction): chatWidthFraction = fraction
            }
        }
        if decision.destination == .hideChat || decision.destination == .hideCanvas { dismissComposer() }
    }

    private func layoutAnimation(initialVelocity: Double = 0) -> Animation? {
        reduceMotion ? nil : .interpolatingSpring(duration: 0.3, bounce: 0, initialVelocity: initialVelocity)
    }

    private func toggleReplies() {
        if repliesExpanded { dismissComposer() }
        withAnimation(layoutAnimation()) {
            resizingChatExtent = nil
            chatFocused = false
            repliesExpanded.toggle()
        }
    }

    private var restoreChatControl: some View {
        Button(action: toggleReplies) {
            Label("Chat", systemImage: chatSide == .left ? "sidebar.left" : "sidebar.right")
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .foregroundStyle(Color.charcoal)
                .background(Color.panelBackground, in: Capsule())
                .overlay(Capsule().stroke(Color.charcoal.opacity(0.16)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show chat")
        .accessibilityValue("Collapsed")
        .accessibilityIdentifier("canvas.restoreChat")
    }

    private var drawingSurface: some View {
        ZStack {
            CanvasView(drawing: $vm.drawing, backgroundColor: canvasBackground.uiColor, isDrawingActive: !composerFocused && !chatFocused, onFirstStroke: vm.onFirstStroke, onClear: {
                vm.clear()
                triggerClearHaptic()
                hasSeenClearHint = true
                showClearHint = false
            })
                .background(canvasBackground.color)
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
                HStack(alignment: .top, spacing: 6) {
                    Button {
                        appState.currentPage = .landing
                    } label: {
                        Image(systemName: "house")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.charcoal.opacity(0.6))
                            .frame(width: 44, height: 44)
                            .background(Color.sandstone.opacity(0.7))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Home")

                    backgroundControl

                    darkModeControl

                    ConnectionDot(isConnected: connectionMonitor.isConnected)
                        .padding(.top, 18)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                Spacer()
                if let connectionMessage {
                    Text(connectionMessage)
                        .font(.callout)
                        .foregroundStyle(Color.charcoal)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(Color.limestone.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
                        .padding(16)
                        .accessibilityIdentifier("canvas.connectionStatus")
                        .allowsHitTesting(false)
                }
            }

            // Send button (middle-right, on canvas)
            HStack {
                Spacer()
                Button(action: castCurrent) {
                    Group {
                        if vm.isCasting {
                            ProgressView()
                                .tint(Color.onAccent)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 24, weight: .medium))
                        }
                    }
                        .foregroundStyle(Color.onAccent)
                        .frame(width: 56, height: 56)
                        .background(Color.ochre)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.15), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .opacity(canSend ? 1.0 : 0.5)
                .accessibilityLabel(vm.isCasting ? "Sending drawing" : "Send drawing")
                .accessibilityHint(connectionMonitor.requiresCodexThread == true ? "Sends to the selected Codex chat." : "Sends to the connected server.")
                .accessibilityIdentifier("canvas.send")
                .padding(.trailing, 16)
            }
        }
    }

    private var darkModeControl: some View {
        Button {
            darkModeEnabled.toggle()
        } label: {
            Image(systemName: darkModeEnabled ? "sun.max" : "moon")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.charcoal)
                .frame(width: 44, height: 44)
                .background(Color.sandstone.opacity(0.9), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dark mode")
        .accessibilityValue(darkModeEnabled ? "On" : "Off")
        .accessibilityHint(darkModeEnabled ? "Switches to the light interface and its saved canvas background." : "Switches to the dark interface and its saved canvas background.")
        .accessibilityIdentifier("canvas.darkMode")
    }

    private var backgroundControl: some View {
        Button {
            showBackgroundPicker = true
        } label: {
            Image(systemName: "paintpalette")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.charcoal)
                .frame(width: 44, height: 44)
                .background(Color.sandstone.opacity(0.9), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Canvas background")
        .accessibilityValue(canvasBackground.displayName)
        .accessibilityIdentifier("canvas.background")
        .popover(isPresented: $showBackgroundPicker) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Canvas background")
                        .font(.headline)
                    Spacer()
                    Button("Done") { showBackgroundPicker = false }
                        .accessibilityIdentifier("canvas.backgroundDone")
                }
                ForEach(CanvasBackground.presets, id: \.rawValue) { preset in
                    Button {
                        setCanvasBackground(preset)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(preset.color)
                                .overlay(Circle().strokeBorder(Color.gray.opacity(0.5), lineWidth: 1))
                                .frame(width: 28, height: 28)
                            Text(preset.displayName)
                            Spacer()
                            if canvasBackground == preset {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.burntOchre)
                            }
                        }
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .background(canvasBackground == preset ? Color.limestone : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("canvas.background.\(preset.rawValue)")
                    .accessibilityAddTraits(canvasBackground == preset ? [.isSelected] : [])
                }
                Divider()
                ColorPicker("Custom color", selection: Binding(
                    get: { canvasBackground.color },
                    set: { setCanvasBackground(CanvasBackground(color: UIColor($0))) }
                ), supportsOpacity: false)
                .frame(minHeight: 44)
                .accessibilityIdentifier("canvas.backgroundCustom")
                Text("Changes the canvas background for \(darkModeEnabled ? "dark" : "light") mode. Use the sun or moon button to change the interface.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("The background is included in sent drawings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if canvasBackground.isDark {
                    Text("Choose a light pen on a dark background.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(Color.charcoal)
            .padding(16)
            .frame(width: 300)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func setCanvasBackground(_ background: CanvasBackground) {
        if darkModeEnabled {
            darkCanvasBackgroundHex = background.rawValue
        } else {
            canvasBackgroundHex = background.rawValue
        }
    }

    private func castCurrent() {
        guard canSend else { return }
        let requiresThread = connectionMonitor.requiresCodexThread == true
        if requiresThread, let target = selectedTarget {
            guard let data = canvasSnapshot() else { return }
            vm.isCasting = true
            vm.castError = nil
            Task {
                defer { vm.isCasting = false }
                do {
                    let confirmed = try await appState.codexConversation.sendDrawing(data, to: target)
                    vm.showCastSuccess = confirmed
                } catch {
                    vm.castError = error.localizedDescription
                }
            }
            triggerCastHaptic()
            return
        }
        vm.cast(
            combo: nil,
            networkService: network,
            offlineQueue: offlineQueue,
            serverURL: connectionMonitor.serverURL,
            isConnected: connectionMonitor.isConnected,
            pairingCode: pairingCode,
            backgroundColor: canvasBackground.uiColor
        )
        triggerCastHaptic()
    }

    private func chooseChat() {
        dismissComposer()
        if let url = connectionMonitor.serverURL { pickerServer = PickerServer(url: url) }
    }

    private func canvasSnapshot() -> Data? {
        guard !vm.drawing.strokes.isEmpty else { return nil }
        return vm.drawing.exportPNG(backgroundColor: canvasBackground.uiColor)
    }

    private func dismissComposer() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        composerFocused = false
    }

    private func toggleChatFocus(isFillingPage: Bool) {
        dismissComposer()
        withAnimation(layoutAnimation()) {
            resizingChatExtent = nil
            repliesExpanded = true
            chatFocused = !isFillingPage
        }
    }
}

