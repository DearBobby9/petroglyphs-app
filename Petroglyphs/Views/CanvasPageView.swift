import SwiftUI
import PencilKit
import PhotosUI
import UniformTypeIdentifiers

struct CanvasPageView: View {
    @Environment(AppState.self) var appState
    @Environment(ConnectionMonitor.self) var connectionMonitor
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("pairingCode") private var pairingCode: String = ""
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false
    @AppStorage("codexRepliesExpanded") private var repliesExpanded = true
    @AppStorage("codexChatSide") private var chatSideRawValue = CanvasChatSide.right.rawValue
    @AppStorage("codexChatWidthFraction") private var chatWidthFraction = CanvasChatFrames.defaultChatFraction
    @AppStorage("codexCanvasCollapsed") private var chatFocused = false
    private var vm: CanvasViewModel { appState.canvasViewModel }
    @State private var showReferenceFiles = false
    @State private var showReferencePhotos = false
    @State private var referencePhoto: PhotosPickerItem?
    @State private var isSelectingExportBounds = false
    @State private var canvasPreviewItem: CodexImagePreviewItem?
    @State private var showConnectionSettings = false
    @State private var showSavedDrafts = false
    @State private var pickerServer: PickerServer?
    @State private var showBackgroundPicker = false
    @State private var composerFocused = false
    @State private var chatMinimumHeight: CGFloat = 360
    @State private var resizingChatExtent: CGFloat?
    @State private var modelSettings = CodexModelSettingsModel()
    @State private var modelSettingsRefreshID = 0
    private let network = NetworkService()
    @State private var offlineQueue = OfflineQueue()

    private struct PickerServer: Identifiable {
        let url: URL
        var creationOnly = false
        var independent = false
        var id: String { "\(url.absoluteString):\(creationOnly)" }
    }

    private struct ConversationRequest: Equatable {
        let target: CodexChatTarget?
        let isActive: Bool
    }

    private struct ModelSettingsRequest: Equatable {
        let serverURL: URL?
        let hostId: String?
        let threadId: String?
        let isActive: Bool
        let refreshID: Int
    }

    private var newChat: CodexProjectCreationModel? {
        guard appState.newCodexChat?.serverURL == connectionMonitor.serverURL else { return nil }
        return appState.newCodexChat
    }

    private var modelSettingsRequest: ModelSettingsRequest {
        ModelSettingsRequest(serverURL: connectionMonitor.serverURL,
                             hostId: newChat?.host.id ?? selectedTarget?.host.id,
                             threadId: newChat == nil ? selectedTarget?.thread.id : nil,
                             isActive: scenePhase == .active, refreshID: modelSettingsRefreshID)
    }

    private var selectedTarget: CodexChatTarget? {
        guard appState.selectedCodexChat?.serverURL == connectionMonitor.serverURL else { return nil }
        return appState.selectedCodexChat
    }

    private var chatSide: CanvasChatSide { CanvasChatSide(rawValue: chatSideRawValue) ?? .right }

    private var canvasBackground: CanvasBackground { vm.background }

    private var hasReplyPanel: Bool {
        connectionMonitor.requiresCodexThread == true || selectedTarget != nil || newChat != nil
    }

    private var canSend: Bool {
        guard !vm.isCasting, vm.hasContent else { return false }
        if hasReplyPanel {
            if let newChat {
                return newChat.request == nil && newChat.project.supportsFirstMessageAttachments
                    && newChat.attachments.count < CodexAttachmentImporter.maximumCount
            }
            guard let target = selectedTarget else { return false }
            return appState.codexConversation.session(for: target).draft.attachments.count < CodexAttachmentImporter.maximumCount
        }
        return connectionMonitor.serverURL != nil && connectionMonitor.requiresCodexThread == false
    }

    private var connectionMessage: String? {
        guard connectionMonitor.serverURL != nil else { return "Open Connection settings to connect your Mac." }
        guard let requiresThread = connectionMonitor.requiresCodexThread else {
            return connectionMonitor.isConnected ? "Checking destination…" : "Waiting for the server connection…"
        }
        if requiresThread && !connectionMonitor.isConnected {
            return "The Mac bridge is unreachable. Your drawing and draft stay here."
        }
        if requiresThread, let newChat {
            if newChat.request != nil { return "The first message has been submitted. Check its status in chat." }
            if !newChat.project.supportsFirstMessageAttachments {
                return "This destination has not verified first-message image support. Choose another destination or start with text."
            }
            if newChat.attachments.count >= CodexAttachmentImporter.maximumCount {
                return "This message already has \(CodexAttachmentImporter.maximumCount) images. Remove an image before adding the canvas."
            }
            return "Add a canvas snapshot to the first message."
        }
        if requiresThread && selectedTarget == nil {
            return "Choose a Codex chat before sending."
        }
        if requiresThread, let error = appState.targetError { return error }
        if requiresThread, let reason = selectedTarget?.host.unavailabilityReason {
            return reason
        }
        if requiresThread, let target = selectedTarget,
           let reason = modelSettings.validationMessage(for: appState.codexConversation.session(for: target).draft.modelSelection, hasImages: true) { return reason }
        return nil
    }

    var body: some View {
        @Bindable var appState = appState

        ZStack {
            Color.limestone.ignoresSafeArea()
            GeometryReader { geometry in
                let useSidebar = CanvasChatFrames.supportsSideBySide(in: geometry.size, accessibilityText: dynamicTypeSize.isAccessibilitySize)
                let availableSize = CGSize(width: max(0, geometry.size.width - 32), height: max(0, geometry.size.height - 24))
                let compactWorkspace = !useSidebar && !CanvasChatFrames.supportsStacked(in: availableSize.height, chatMinimumHeight: chatMinimumHeight)
                let chatFillsPage = hasReplyPanel && repliesExpanded && (chatFocused || compactWorkspace)
                let stackedChatHeight = CanvasChatFrames.stackedHeight(in: availableSize.height, chatMinimumHeight: chatMinimumHeight)
                let mode: CanvasChatLayoutMode = !hasReplyPanel ? .canvasOnly : (useSidebar ? .sideBySide : .stacked)
                let canResize = hasReplyPanel && useSidebar && repliesExpanded && !chatFillsPage
                let controls = layoutControls(availableWidth: availableSize.width, canResize: canResize)
                let expandedExtent = useSidebar
                    ? CanvasChatFrames.chatExtent(fraction: chatWidthFraction, availableWidth: availableSize.width)
                    : stackedChatHeight + CanvasChatFrames.stackedSpacing / 2
                let fullExtent = useSidebar ? availableSize.width : availableSize.height
                let chatExtent = resizingChatExtent ?? (repliesExpanded ? (chatFillsPage ? fullExtent : expandedExtent) : 0)
                CanvasChatLayout(mode: mode, side: chatSide, chatExtent: chatExtent) {
                    CanvasChatPane(minimumWidth: useSidebar ? CanvasChatFrames.minimumCanvasWidth : 0,
                                   minimumHeight: useSidebar ? 0 : 160,
                                   alignment: chatSide == .left ? .trailing : .leading) {
                        drawingSurface
                    }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("canvas.surface")
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
                                       minimumHeight: 0,
                                       alignment: chatSide == .left ? .leading : .trailing) {
                            CodexRepliesPanel(
                                store: appState.codexConversation,
                                target: selectedTarget,
                                newChat: newChat,
                                modelSettings: modelSettings,
                                isConnected: connectionMonitor.isConnected,
                                isFocused: chatFillsPage,
                                canSend: connectionMonitor.isConnected && appState.canSendToSelectedTarget,
                                onChooseChat: chooseChat,
                                onNewChat: chooseNewChatProject,
                                onCancelNewChat: { dismissComposer(); appState.newCodexChat = nil },
                                onCreated: { thread, draft in
                                    dismissComposer()
                                    appState.finishNewChat(thread, from: draft)
                                },
                                onRefreshModels: { modelSettingsRefreshID += 1 },
                                onAddCanvas: canvasSnapshot,
                                onComposerFocusChanged: { focused in
                                    withAnimation(layoutAnimation()) { composerFocused = focused }
                                },
                                onExpand: { toggleChatFocus(isFillingPage: chatFillsPage) },
                                layoutControls: controls,
                                reservesTopTrailingControl: chatFillsPage || (useSidebar && chatSide == .right),
                                onConnectionSettings: { showConnectionSettings = true },
                                onCanvasFilename: { vm.snapshotFilename },
                                onRefreshTarget: { Task { await appState.refreshSelectedTarget() } },
                                sendUnavailableReason: connectionMonitor.isConnected
                                    ? (appState.targetError ?? selectedTarget?.host.unavailabilityReason)
                                    : "The Mac bridge is unreachable. Your draft is saved.",
                                onShowDrafts: { appState.refreshCreationDrafts(); showSavedDrafts = true }
                            )
                        }
                        .allowsHitTesting(repliesExpanded)
                        .accessibilityHidden(!repliesExpanded)
                    }
                }
                .transaction(value: chatExtent) { transaction in
                    // AppStorage updates can arrive without the button's animation.
                    // Preserve the release spring's velocity and direct drag tracking.
                    if reduceMotion {
                        transaction.animation = nil
                    } else if !transaction.disablesAnimations && resizingChatExtent == nil && transaction.animation == nil {
                        transaction.animation = layoutAnimation()
                    }
                }
                .coordinateSpace(name: "canvas-chat-workspace")
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if hasReplyPanel {
                        if compactWorkspace {
                            Button(repliesExpanded ? "Canvas" : "Chat", systemImage: repliesExpanded ? "pencil.tip" : "bubble.left.and.bubble.right", action: toggleReplies)
                                .buttonStyle(.borderedProminent).tint(Color.ochre)
                                .frame(minHeight: 44).padding(12)
                                .accessibilityIdentifier("canvas.compactMode")
                        } else { chatVisibilityControl.padding(16) }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("canvas.workspace")
                .accessibilityValue("Chat on \(chatSide.rawValue), \(chatFillsPage ? "canvas hidden" : (repliesExpanded ? "split" : "chat hidden"))")
                .onChange(of: availableSize.width) { _, _ in resizingChatExtent = nil }
                .onChange(of: useSidebar) { _, _ in resizingChatExtent = nil }
                .onPreferenceChange(CodexChatChromeHeightKey.self) { heights in
                    let readingHeight: CGFloat = dynamicTypeSize.isAccessibilitySize ? 180 : 120
                    chatMinimumHeight = max(360, heights.values.reduce(0, +) + readingHeight)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let reference = appState.codexConversation.lastSubmission,
               newChat != nil || !repliesExpanded || selectedTarget.map({ CodexConversationKey($0) }) != CodexConversationKey(reference.target) {
                CodexWorkspaceRequestStatus(reference: reference, store: appState.codexConversation) {
                    appState.selectedCodexChat = reference.target
                    appState.newCodexChat = nil
                    appState.codexConversation.setReadingPosition("user:\(reference.id)", atBottom: false, for: reference.target)
                    repliesExpanded = true
                    chatFocused = true
                }
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
        .task(id: ConversationRequest(target: newChat == nil ? selectedTarget : nil, isActive: scenePhase == .active)) {
            guard scenePhase == .active, newChat == nil, let target = selectedTarget else { return }
            await appState.codexConversation.observe(target: target)
        }
        .task(id: "\(selectedTarget.map { CodexConversationKey($0).storageID } ?? "none"):\(scenePhase == .active):\(connectionMonitor.isConnected)") {
            guard scenePhase == .active, connectionMonitor.isConnected, newChat == nil else { return }
            await appState.refreshSelectedTarget()
        }
        .task(id: modelSettingsRequest) {
            let request = modelSettingsRequest
            guard request.isActive, let serverURL = request.serverURL, let hostId = request.hostId else { return }
            await modelSettings.observe(from: serverURL, hostId: hostId, threadId: request.threadId)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            modelSettingsRefreshID += 1
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
            if appState.newCodexChat?.serverURL != connectionMonitor.serverURL { appState.newCodexChat = nil }
            pickerServer = nil
        }
        .sheet(item: $pickerServer) { server in
            CodexThreadPickerView(serverURL: server.url, selection: $appState.selectedCodexChat,
                                  creationOnly: server.creationOnly,
                                  initialHostID: newChat?.host.id ?? selectedTarget?.host.id,
                                  onChoose: { appState.newCodexChat = nil },
                                  onNewChat: { host, project in
                                      if server.independent { appState.startIndependentChat(project: project, host: host, serverURL: server.url) }
                                      else { appState.startNewChat(project: project, host: host, serverURL: server.url) }
                                  })
                .presentationDetents([.large])
        }
        .photosPicker(isPresented: $showReferencePhotos, selection: $referencePhoto, matching: .images)
        .onChange(of: referencePhoto) { _, photo in
            guard let photo else { return }
            Task {
                defer { referencePhoto = nil }
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self) else { throw CodexAttachmentImporter.ImportError.unsupported }
                    try vm.setReferenceImage(data: data, name: "Imported photo", sourceID: "photo:\(UUID().uuidString.lowercased())")
                } catch { vm.castError = error.localizedDescription }
            }
        }
        .fileImporter(isPresented: $showReferenceFiles, allowedContentTypes: [.png, .jpeg]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                try vm.setReferenceImage(data: Data(contentsOf: url), name: url.lastPathComponent,
                                         sourceID: "file:\(url.lastPathComponent)")
            } catch { vm.castError = error.localizedDescription }
        }
        .sheet(item: $canvasPreviewItem) { item in
            CodexImagePreview(items: [item], selectedID: item.id)
        }
        .sheet(isPresented: $showConnectionSettings) { ServerSettingsSheet() }
        .sheet(isPresented: $showSavedDrafts) {
            CodexDraftsSheet {
                if let url = connectionMonitor.serverURL {
                    pickerServer = PickerServer(url: url, creationOnly: true, independent: true)
                }
            }
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
        reduceMotion ? nil : .interpolatingSpring(duration: 0.38, bounce: 0, initialVelocity: initialVelocity)
    }

    private func toggleReplies() {
        if repliesExpanded { dismissComposer() }
        withAnimation(layoutAnimation()) {
            resizingChatExtent = nil
            chatFocused = false
            repliesExpanded.toggle()
        }
    }

    private var chatVisibilityControl: some View {
        Button(action: toggleReplies) {
            Image(systemName: repliesExpanded ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(repliesExpanded ? Color.onAccent : Color.charcoal)
                .frame(width: 44, height: 44)
                .background(repliesExpanded ? Color.ochre : Color.sandstone.opacity(0.9), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: repliesExpanded)
        .accessibilityLabel(repliesExpanded ? "Hide chat" : "Show chat")
        .accessibilityValue(repliesExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(repliesExpanded ? "Keeps the current conversation and draft." : "Opens the selected conversation.")
        .accessibilityIdentifier("canvas.repliesToggle")
    }

    private var drawingSurface: some View {
        @Bindable var vm = vm
        return ZStack {
            CanvasView(viewModel: vm, isDrawingActive: !composerFocused && !chatFocused,
                       isSelectingExportBounds: isSelectingExportBounds,
                       onExportBoundsSelected: { isSelectingExportBounds = false })
                .background(canvasBackground.color)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Overlays
            WipeAnimationOverlay(isShowing: $vm.showWipeAnimation)
            CastSuccessOverlay(isShowing: $vm.showCastSuccess)

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

                    Menu {
                        Button("Undo", systemImage: "arrow.uturn.backward") { vm.undo() }
                            .disabled(!vm.canUndo).keyboardShortcut("z", modifiers: .command)
                        Button("Redo", systemImage: "arrow.uturn.forward") { vm.redo() }
                            .disabled(!vm.canRedo).keyboardShortcut("z", modifiers: [.command, .shift])
                        Divider()
                        Button("Drafts and pending", systemImage: "tray.full") {
                            appState.refreshCreationDrafts()
                            showSavedDrafts = true
                        }
                        Divider()
                        Button("Clear ink", systemImage: "trash", role: .destructive) {
                            vm.clear()
                            triggerClearHaptic()
                        }
                        .disabled(vm.drawing.strokes.isEmpty)
                        Text("Undo is available while this app stays open. Saved ink is restored after restart.")
                        Section("Reference image") {
                            Button("Import result image", systemImage: "folder") { showReferenceFiles = true }
                            Button("Choose photo", systemImage: "photo") { showReferencePhotos = true }
                            if let reference = vm.referenceImage {
                                Text("Locked reference: \(reference.name)")
                                Button("Remove reference image", systemImage: "photo.badge.minus", role: .destructive) { vm.clearReferenceImage() }
                            }
                        }
                        Section("Export area") {
                            Button("Select area", systemImage: "viewfinder") { isSelectingExportBounds = true }
                                .disabled(!vm.hasContent)
                            Button("Full canvas", systemImage: "arrow.up.left.and.arrow.down.right") {
                                do { try vm.setExportBounds(nil) } catch { vm.castError = error.localizedDescription }
                            }
                            .disabled(vm.selectedExportBounds == nil)
                            Button("Preview snapshot", systemImage: "magnifyingglass") {
                                guard let data = vm.snapshot() else { return }
                                canvasPreviewItem = CodexImagePreviewItem(id: UUID().uuidString, name: vm.snapshotFilename, load: { data })
                            }
                            .disabled(!vm.hasContent)
                        }
                    } label: {
                        Image(systemName: "pencil.and.outline").frame(width: 44, height: 44)
                            .background(Color.sandstone.opacity(0.9), in: Circle())
                    }
                    .accessibilityLabel("Canvas editing")
                    .accessibilityIdentifier("canvas.editing")

                    Button { showConnectionSettings = true } label: {
                        ConnectionDot(isConnected: connectionMonitor.isConnected)
                            .frame(width: 44, height: 44)
                            .background(Color.sandstone.opacity(0.9), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Connection settings")
                    .accessibilityIdentifier("canvas.connectionSettings")
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                Spacer()
                if isSelectingExportBounds {
                    HStack {
                        Text("Drag over the canvas to select the snapshot area.").font(.caption)
                        Button("Cancel") { isSelectingExportBounds = false }.frame(minHeight: 44)
                    }
                    .padding(8).background(Color.panelBackground, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 16)
                }
                if let error = vm.storageError {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(error, systemImage: "exclamationmark.triangle")
                        Button("Retry saving canvas") { vm.save() }
                    }
                    .font(.caption).foregroundStyle(Color.rust)
                    .padding(12).background(Color.panelBackground, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("canvas.storageError")
                }
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
                            Image(systemName: hasReplyPanel ? "plus.bubble.fill" : "paperplane.fill")
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
                .accessibilityLabel(hasReplyPanel ? "Add canvas to message" : (vm.isCasting ? "Sending drawing" : "Send drawing"))
                .accessibilityHint(hasReplyPanel ? "Adds a fixed snapshot. Review the complete text and images, then send once." : "Sends to the connected server.")
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
        .accessibilityHint(darkModeEnabled ? "Switches the interface to light mode." : "Switches the interface to dark mode.")
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
                Text("This background belongs to the canvas and stays the same when the interface changes.")
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
        vm.background = background
    }

    private func castCurrent() {
        guard canSend else { return }
        if hasReplyPanel {
            guard let data = canvasSnapshot() else { return }
            do {
                let image = CodexImportedImage(data: data, name: vm.snapshotFilename, mimeType: "image/png")
                if let newChat { try newChat.addImage(image) }
                else if let target = selectedTarget { try appState.codexConversation.addImage(image, for: target) }
                repliesExpanded = true
            } catch { vm.castError = error.localizedDescription }
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

    private func chooseNewChatProject() {
        dismissComposer()
        if let url = connectionMonitor.serverURL { pickerServer = PickerServer(url: url, creationOnly: true) }
    }

    private func canvasSnapshot() -> Data? {
        guard vm.hasContent else { return nil }
        return vm.snapshot()
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

