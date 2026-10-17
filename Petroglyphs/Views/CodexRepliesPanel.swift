import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct CodexRepliesPanel: View {
    let store: CodexConversationStore
    let target: CodexChatTarget?
    let newChat: CodexProjectCreationModel?
    let modelSettings: CodexModelSettingsModel
    let isConnected: Bool
    var isFocused = false
    var canSend = true
    let onChooseChat: () -> Void
    let onNewChat: () -> Void
    let onCancelNewChat: () -> Void
    let onCreated: (CodexThread, CodexProjectCreationModel) -> Void
    let onRefreshModels: () -> Void
    let onAddCanvas: () -> Data?
    let onComposerFocusChanged: (Bool) -> Void
    var onExpand: (() -> Void)? = nil
    var layoutControls: CanvasChatLayoutControls? = nil
    var reservesTopTrailingControl = false
    var onConnectionSettings: () -> Void = {}
    var onCanvasFilename: () -> String = { "Canvas.png" }
    var onRefreshTarget: () -> Void = {}
    var sendUnavailableReason: String? = nil
    var onShowDrafts: () -> Void = {}
    @State private var showDiagnostics = false

    private var session: CodexConversationSession? { target.map { store.session(for: $0) } }

    var body: some View {
        GeometryReader { geometry in
        VStack(spacing: 0) {
            header.chatChromeHeight("header")
            Divider()
            if let newChat {
                CodexNewChatPanel(model: newChat, modelSettings: modelSettings, isConnected: isConnected,
                                  onCancel: onCancelNewChat, onChooseDestination: onNewChat,
                                  onRefreshModels: onRefreshModels, onFocusChanged: onComposerFocusChanged,
                                  onCreated: { onCreated($0, newChat) }, onAddCanvas: onAddCanvas, onCanvasFilename: onCanvasFilename)
                    .id(newChat.draftID)
            } else if let target, let session {
                chatContents(target: target, session: session)
                    .id(session.key)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right").font(.largeTitle)
                    Text("Start a conversation").font(.headline)
                    Text("Continue a conversation with text, pictures, and your canvas.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("New chat", systemImage: "square.and.pencil", action: onNewChat)
                        .buttonStyle(.borderedProminent).tint(Color.ochre).foregroundStyle(Color.onAccent)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("chat.newChat")
                    Button("Choose an existing chat", action: onChooseChat)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("chat.destination")
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.charcoal)
        .background(Color.panelBackground, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("codex.repliesPanel")
        .sheet(isPresented: $showDiagnostics) {
            if let target { CodexDiagnosticsSheet(target: target) }
        }
        .environment(\.codexComposerMaximumHeight, max(110, min(280, geometry.size.height * 0.48)))
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Chat").font(.headline).lineLimit(1)
            }
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Menu {
                Button {
                    if let newChat { Task { await newChat.checkStatus() } }
                    else if let target { Task { await store.refresh(for: target) } }
                    onRefreshModels()
                    onRefreshTarget()
                } label: { Label(newChat == nil ? "Refresh conversation" : "Refresh creation status", systemImage: "arrow.clockwise") }
                .disabled((target == nil && newChat == nil) || (newChat?.isBusy ?? (session?.isRefreshing == true)))
                .accessibilityIdentifier("codex.refreshReplies")
                Button("Drafts and pending", systemImage: "tray.full", action: onShowDrafts)
                Button("Connection settings", systemImage: "network", action: onConnectionSettings)
                Button("Bridge diagnostics", systemImage: "stethoscope") { showDiagnostics = true }
                    .disabled(target == nil)
                if let layoutControls { CanvasChatLayoutMenuItems(controls: layoutControls) }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Chat options")
            .accessibilityIdentifier("chat.moreMenu")
            if let onExpand {
                Button(action: onExpand) {
                    Image(systemName: isFocused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFocused ? "Return to canvas" : "Expand chat")
                .accessibilityIdentifier("chat.expand")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, reservesTopTrailingControl ? 68 : 12)
        .padding(.vertical, 8)
    }

    private func chatContents(target: CodexChatTarget, session: CodexConversationSession) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button(action: onChooseChat) {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(target.thread.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Label([target.host.name, target.projectName ?? target.thread.projectName ?? target.thread.cwd].compactMap { $0 }.joined(separator: " · "), systemImage: target.host.kind == "remote" ? "network" : "desktopcomputer")
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change chat: \(target.thread.displayTitle), \(target.host.name)")
                .accessibilityIdentifier("chat.destination")
                Button(action: onNewChat) {
                    Image(systemName: "square.and.pencil").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New chat")
                .accessibilityIdentifier("chat.newChat")
                .padding(.trailing, 8)
            }
            .chatChromeHeight("destination")

            if let error = session.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).font(.caption).textSelection(.enabled)
                }
                .foregroundStyle(Color.rust)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .accessibilityIdentifier("chat.loadError")
                .chatChromeHeight("error")
            }
            if let receiptError = session.receiptError {
                Label("Delivery check: \(receiptError)", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(Color.rust).padding(.horizontal, 14).padding(.vertical, 6)
            }
            Divider()
            CodexConversationTimeline(store: store, target: target, session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            CodexMessageComposer(store: store, target: target, session: session,
                                 canSend: canSend, onAddCanvas: onAddCanvas,
                                 onFocusChanged: onComposerFocusChanged,
                                 modelSettings: modelSettings, onRefreshModels: onRefreshModels, onCanvasFilename: onCanvasFilename,
                                 sendUnavailableReason: sendUnavailableReason)
                .chatChromeHeight("composer")
        }
    }
}

private struct CodexConversationTimeline: View {
    let store: CodexConversationStore
    let target: CodexChatTarget
    let session: CodexConversationSession
    @State private var reading = CodexReadingCoordinator()
    @State private var scrollHandle = CodexScrollHandle()
    @State private var hasNewMessages = false
    private let bottomID = "conversation-bottom"

    private var revision: String {
        session.messages.map { "\($0.displayID):\($0.text.hashValue):\($0.state.rawValue):\($0.attachments.count)" }.joined(separator: "|")
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if session.beforeCursor != nil {
                            Button {
                                let anchor = visibleAnchor
                                let wasAtBottom = session.isAtBottom
                                Task {
                                    await store.loadOlder(for: target)
                                    if let anchor { restore(anchor, proxy: proxy) }
                                    else if wasAtBottom { scrollTimeline(proxy, to: bottomID, anchor: .bottom) }
                                }
                            } label: {
                                HStack {
                                    if session.isLoadingOlder { ProgressView().controlSize(.small) }
                                    Text("Load earlier messages")
                                }
                                .font(.callout)
                                .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .disabled(session.isLoadingOlder)
                            .accessibilityIdentifier("chat.loadOlder")
                        }
                        if session.messages.isEmpty {
                            if session.isLoading {
                                ProgressView("Loading conversation…").frame(maxWidth: .infinity).padding(.vertical, 30)
                            } else {
                                VStack(spacing: 8) {
                                    Text("Continue this chat").font(.headline)
                                    Text("Write a message or add an image below.").font(.callout).foregroundStyle(.secondary)
                                }
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 30)
                            }
                        }
                        ForEach(CodexConversationTurn.group(session.messages)) { turn in
                            CodexConversationTurnView(turn: turn, target: target, store: store)
                        }
                        if session.runState == "running" || session.runState == "waiting" {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(session.runState == "waiting" ? "Waiting" : "Running", systemImage: session.runState == "waiting" ? "pause.circle" : "ellipsis.bubble")
                                    .font(.caption.weight(.semibold))
                                Text("\(target.host.name) · \(target.thread.displayTitle)").font(.caption)
                            }
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("chat.runState")
                        }
                        CodexExecutionControlsView(target: target, runState: session.runState,
                                                   latestTurnID: session.history.last?.turnId)
                        Color.clear.frame(height: 1).id(bottomID)
                    }
                    .padding(14)
                    .background(CodexScrollCapture(handle: scrollHandle))
                    .background(GeometryReader { content in
                        Color.clear.preference(key: ConversationContentFrameKey.self,
                                               value: content.frame(in: .named("conversation-scroll")))
                    })
                }
                .coordinateSpace(name: "conversation-scroll")
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("codex.repliesList")
                .onPreferenceChange(MessagePositionKey.self) {
                    InteractionDiagnostics.shared.record(.chatRowsPreference)
                    reading.rowPositions = $0; finishRestoration(); scheduleReadingSave()
                }
                .onPreferenceChange(CodexReadingBlockKey.self) {
                    InteractionDiagnostics.shared.record(.chatBlocksPreference)
                    reading.blockPositions = $0; finishRestoration(); scheduleReadingSave()
                }
                .onPreferenceChange(ConversationContentFrameKey.self) { frame in
                    InteractionDiagnostics.shared.record(.chatContentPreference)
                    guard let frame else { return }
                    let viewport = CodexReadingViewport(contentFrame: frame, viewportHeight: geometry.size.height)
                    guard let followsLatest = reading.updateMetrics(viewport, wasFollowingLatest: session.isAtBottom) else {
                        InteractionDiagnostics.shared.record(.chatMetricsIgnored)
                        return
                    }
                    InteractionDiagnostics.shared.record(.chatMetricsChanged, geometry: [.chatContentFrame: [
                        Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)
                    ]])
                    if followsLatest != session.isAtBottom { saveReadingPosition(atBottom: followsLatest) }
                    if followsLatest {
                        if hasNewMessages { hasNewMessages = false }
                    } else { scheduleReadingSave() }
                }
                .simultaneousGesture(DragGesture(minimumDistance: 3).onChanged { _ in
                    reading.userIsScrolling = true
                }.onEnded { _ in
                    let atBottom = reading.readingViewport?.isAtBottom ?? session.isAtBottom
                    saveReadingPosition(atBottom: atBottom)
                    reading.userIsScrolling = false
                })
                .onChange(of: revision, initial: true) { _, _ in
                    guard !session.messages.isEmpty else { return }
                    if !reading.restoredPosition {
                        reading.restoredPosition = true
                        if !session.isAtBottom, let id = session.readingMessageID,
                           session.messages.contains(where: { $0.displayID == id }) {
                            restore(CodexReadingAnchor(messageID: id, blockID: session.readingBlockID ?? id,
                                                       fraction: session.readingBlockFraction ?? 0), proxy: proxy)
                        } else { scrollTimeline(proxy, to: bottomID, anchor: .bottom) }
                    } else if session.isAtBottom && !reading.userIsScrolling {
                        scrollTimeline(proxy, to: bottomID, anchor: .bottom)
                    } else { hasNewMessages = true }
                }
                .task(id: geometry.size) {
                    InteractionDiagnostics.shared.record(.chatGeometry, geometry: [.chatGeometry: [
                        Double(geometry.size.width), Double(geometry.size.height)
                    ]])
                    reading.viewportHeight = geometry.size.height
                    let wasFollowingLatest = session.isAtBottom
                    let readingAnchor = session.readingMessageID.map {
                        CodexReadingAnchor(messageID: $0, blockID: session.readingBlockID ?? $0,
                                           fraction: session.readingBlockFraction ?? 0)
                    }
                    await Task.yield()
                    guard !Task.isCancelled, !reading.userIsScrolling else { return }
                    if wasFollowingLatest && session.isAtBottom { scrollTimeline(proxy, to: bottomID, anchor: .bottom) }
                    else if let readingAnchor { restore(readingAnchor, proxy: proxy) }
                }
                .onDisappear {
                    reading.savePositionTask?.cancel()
                    if reading.pendingRestore == nil { saveReadingPosition(atBottom: session.isAtBottom) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !session.isAtBottom {
                        Button {
                            session.isAtBottom = true
                            hasNewMessages = false
                            store.setReadingPosition(nil, atBottom: true, for: target)
                            withAnimation(.easeOut(duration: 0.2)) { scrollTimeline(proxy, to: bottomID, anchor: .bottom) }
                        } label: {
                            Label(hasNewMessages ? "New messages" : "Latest", systemImage: "arrow.down")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12).frame(minHeight: 44)
                                .background(Color.sandstone, in: Capsule())
                                .overlay(Capsule().stroke(Color.charcoal.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .padding(12)
                        .accessibilityIdentifier("chat.latest")
                    }
                }
            }
        }
    }

    private func scrollTimeline(_ proxy: ScrollViewProxy, to id: String, anchor: UnitPoint) {
        InteractionDiagnostics.shared.record(.chatScrollToBegin)
        defer { InteractionDiagnostics.shared.record(.chatScrollToEnd) }
        proxy.scrollTo(id, anchor: anchor)
    }

    private var visibleAnchor: CodexReadingAnchor? {
        var candidates = reading.blockPositions
        for (id, frame) in reading.rowPositions where !candidates.values.contains(where: { $0.messageID == id }) {
            candidates[id] = CodexReadingBlock(messageID: id, frame: frame)
        }
        return CodexReadingAnchor.visible(in: candidates, viewportHeight: reading.viewportHeight)
    }

    private func saveReadingPosition(atBottom: Bool) {
        guard reading.pendingRestore == nil else { return }
        let anchor = visibleAnchor
        store.setReadingPosition(anchor?.messageID, atBottom: atBottom, for: target,
                                 blockID: anchor?.blockID, blockFraction: anchor?.fraction)
    }

    private func scheduleReadingSave() {
        guard reading.restoredPosition, reading.pendingRestore == nil, !session.isAtBottom else { return }
        InteractionDiagnostics.shared.record(.chatReadingSaveScheduled)
        reading.savePositionTask?.cancel()
        reading.savePositionTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            InteractionDiagnostics.shared.record(.chatReadingSaveCompleted)
            saveReadingPosition(atBottom: false)
        }
    }

    private func restore(_ anchor: CodexReadingAnchor, proxy: ScrollViewProxy) {
        reading.pendingRestore = anchor
        reading.savePositionTask?.cancel()
        let turn = CodexConversationTurn.group(session.messages).first { $0.messages.contains { $0.displayID == anchor.messageID } }
        InteractionDiagnostics.shared.record(.chatRestore, flags: [.chatHasPendingRestore: true, .chatAnchorExists: turn != nil])
        scrollTimeline(proxy, to: turn?.id ?? anchor.messageID, anchor: .top)
        Task { await Task.yield(); finishRestoration() }
    }

    private func finishRestoration() {
        InteractionDiagnostics.shared.record(.chatRestoreAttempt, flags: [
            .chatHasPendingRestore: reading.pendingRestore != nil, .chatHasScrollView: scrollHandle.scrollView != nil
        ])
        guard let anchor = reading.pendingRestore, let scrollView = scrollHandle.scrollView else { return }
        let message = session.messages.first { $0.displayID == anchor.messageID }
        let blockIDs = Set(message.map { message in
            CodexMarkdownDocument(message.text).blocks.map { "\(message.displayID):block:\($0.id)" }
        } ?? [])
        guard let restoration = anchor.restoration(in: reading.blockPositions, messageFrame: reading.rowPositions[anchor.messageID], existingBlockIDs: blockIDs) else {
            InteractionDiagnostics.shared.record(.chatRestoreMissingFrame, flags: [
                .chatAnchorExists: message != nil, .chatAnchorFrameExists: false
            ])
            return
        }
        let previousOffset = scrollView.contentOffset.y
        scrollHandle.restore(frame: restoration.frame, fraction: restoration.fraction)
        if let viewport = reading.readingViewport {
            // This offset was requested by restoration. Make it the baseline so
            // the resulting measurement does not change the saved reading mode.
            reading.readingViewport = CodexReadingViewport(
                contentFrame: viewport.contentFrame.offsetBy(dx: 0, dy: previousOffset - scrollView.contentOffset.y),
                viewportHeight: viewport.viewportHeight)
        }
        reading.pendingRestore = nil
        InteractionDiagnostics.shared.record(.chatRestoreCompleted, flags: [
            .chatHasPendingRestore: false, .chatAnchorExists: message != nil, .chatAnchorFrameExists: true
        ])
    }
}

struct MessagePositionKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

private struct ConversationContentFrameKey: PreferenceKey {
    static var defaultValue: CGRect?
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) { value = nextValue() ?? value }
}

private struct CodexMessageComposer: View {
    @Environment(\.codexComposerMaximumHeight) private var maximumHeight
    let store: CodexConversationStore
    let target: CodexChatTarget
    let session: CodexConversationSession
    let canSend: Bool
    let onAddCanvas: () -> Data?
    let onFocusChanged: (Bool) -> Void
    let modelSettings: CodexModelSettingsModel
    let onRefreshModels: () -> Void
    let onCanvasFilename: () -> String
    let sendUnavailableReason: String?
    @State private var previewAttachment: CodexDraftAttachment?
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var isDropTarget = false

    private var canSubmit: Bool {
        canSend && !session.draft.isEmpty && session.importingCount == 0 && session.draft.text.utf16.count <= 20_000
            && (session.draft.modelSelection == nil || modelSettings.matches(from: target.serverURL, hostId: target.host.id, threadId: target.thread.id))
            && modelSettings.validationMessage(for: session.draft.modelSelection, hasImages: !session.draft.attachments.isEmpty) == nil
    }

    var body: some View {
        CodexComposerScroll(maximumHeight: maximumHeight) {
        VStack(alignment: .leading, spacing: 8) {
            if !session.recoveredDrafts.isEmpty {
                DisclosureGroup("Recovered messages · \(session.recoveredDrafts.count)") {
                    ForEach(session.recoveredDrafts) { recovered in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recovered.draft.text).font(.caption).lineLimit(3)
                            Text("\(recovered.draft.attachments.count) images").font(.caption2).foregroundStyle(.secondary)
                            Button("Edit this message") {
                                do { try store.restoreRecoveredDraft(recovered.id, for: target) }
                                catch { session.draftError = error.localizedDescription }
                            }
                            .frame(minHeight: 44)
                        }
                    }
                    Text("Your current draft will stay in this list when you switch.").font(.caption).foregroundStyle(.secondary)
                }
                .font(.callout)
                .accessibilityIdentifier("chat.recoveredDrafts")
            }

            if !session.draft.attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(session.draft.attachments) { attachment in
                            VStack(spacing: 2) {
                                Button { previewAttachment = attachment } label: {
                                    CodexDraftThumbnail(attachment: attachment, target: target, store: store)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Preview \(attachment.name)")
                                Button {
                                    store.removeAttachment(attachment.id, for: target)
                                } label: {
                                    Label("Remove", systemImage: "xmark.circle.fill").font(.caption).frame(minHeight: 44).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Remove \(attachment.name)")
                                .accessibilityIdentifier("chat.removeAttachment.\(attachment.id)")
                            }
                        }
                    }
                }
                .accessibilityIdentifier("chat.draftAttachments")
            }
            if let error = session.draftError {
                HStack(alignment: .top) {
                    Text(error).font(.caption).foregroundStyle(Color.rust)
                    Spacer(minLength: 0)
                    Button { session.draftError = nil } label: { Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .buttonStyle(.plain).accessibilityLabel("Dismiss draft error")
                }
                .accessibilityIdentifier("chat.draftError")
            }
            if session.stateRestorationFailed {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preserve the unreadable file before saving a new draft. Unconfirmed requests in that file still need to be checked in Desktop.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Preserve original and enable drafts") {
                        do { try store.preserveUnreadableState(for: target) }
                        catch { session.draftError = error.localizedDescription }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("chat.recoverProtectedState")
                }
            }
            if session.importingCount > 0 {
                ProgressView("Adding image…").font(.caption)
            }
            CodexComposerCard(text: Binding(get: { session.draft.text }, set: { store.setDraftText($0, for: target) }),
                              canSubmit: canSubmit, isDropTarget: isDropTarget, hasImages: !session.draft.attachments.isEmpty,
                              sendLabel: session.isBusy ? "Queue message" : "Send message",
                              sendHint: session.isBusy ? "Sends to this chat after its current turn finishes." : "Sends text and attached images to the selected chat.",
                              modelSettings: modelSettings, modelSelection: session.draft.modelSelection,
                              onModelSelectionChange: { store.setDraftModelSelection($0, for: target) },
                              onRefreshModels: onRefreshModels, onFocusChanged: onFocusChanged,
                              onPasteImages: importProviders, onSubmit: send) { attachmentMenu }
            .onDrop(of: [UTType.image], isTargeted: $isDropTarget) { providers in
                importProviders(providers)
                return !providers.isEmpty
            }
            if !canSend {
                Text(sendUnavailableReason ?? "The selected chat is unavailable. Your draft is saved.").font(.caption).foregroundStyle(.secondary)
            } else if session.isBusy {
                Text("Your next message will wait for the current turn.").font(.caption).foregroundStyle(.secondary)
            }
            if session.draft.text.utf16.count > 20_000 {
                Text("Message is over the 20,000-character limit.").font(.caption).foregroundStyle(Color.rust)
            }
        }
        .padding(12)
        }
        .background(Color.panelBackground)
        .sheet(item: $previewAttachment) { attachment in
            CodexImagePreview(items: session.draft.attachments.map { item in
                CodexImagePreviewItem(id: item.id, name: item.name, load: { try await store.imageData(item.messageAttachment, for: target) })
            }, selectedID: attachment.id, onRemove: { store.removeAttachment($0, for: target) })
        }
        .photosPicker(isPresented: $showPhotos, selection: $photos,
                      maxSelectionCount: max(1, CodexAttachmentImporter.maximumCount - session.draft.attachments.count), matching: .images)
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            let originalTarget = target
            session.importingCount += 1
            Task {
                defer { session.importingCount -= 1; photos = [] }
                do {
                    for item in items {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw CodexAttachmentImporter.ImportError.unsupported }
                        let image = try await Task.detached { try CodexAttachmentImporter.normalize(data, name: "Photo") }.value
                        try store.addImage(image, for: originalTarget)
                    }
                } catch { session.draftError = error.localizedDescription }
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            let originalTarget = target
            session.importingCount += 1
            Task {
                defer { session.importingCount -= 1 }
                do {
                    for url in try result.get() {
                        let granted = url.startAccessingSecurityScopedResource()
                        defer { if granted { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        let image = try await Task.detached { try CodexAttachmentImporter.normalize(data, name: url.lastPathComponent) }.value
                        try store.addImage(image, for: originalTarget)
                    }
                } catch { session.draftError = error.localizedDescription }
            }
        }
    }

    private var attachmentMenu: some View {
        Menu {
            Button { showPhotos = true } label: { Label("Photos", systemImage: "photo") }
                .accessibilityIdentifier("chat.photos")
            Button { showFiles = true } label: { Label("Choose image file", systemImage: "folder") }
                .accessibilityIdentifier("chat.files")
            Button {
                guard let data = onAddCanvas() else {
                    session.draftError = "Draw something on the canvas before adding it."
                    return
                }
                do { try store.addImage(CodexImportedImage(data: data, name: onCanvasFilename(), mimeType: "image/png"), for: target) }
                catch { session.draftError = error.localizedDescription }
            } label: { Label("Add current canvas", systemImage: "pencil.tip.crop.circle.badge.plus") }
                .accessibilityIdentifier("chat.attachCanvas")
            PasteButton(supportedContentTypes: [.image]) { importProviders($0) }
                .accessibilityIdentifier("chat.paste")
        } label: {
            Image(systemName: "plus").font(.body.weight(.medium)).frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .disabled(session.draft.attachments.count >= CodexAttachmentImporter.maximumCount)
        .accessibilityLabel("Add attachment")
        .accessibilityHint("Choose photos, image files, paste an image, or add the current canvas.")
        .accessibilityIdentifier("chat.addAttachment")
    }

    private func importProviders(_ providers: [NSItemProvider]) {
        let originalTarget = target
        session.importingCount += 1
        Task {
            defer { session.importingCount -= 1 }
            do {
                for provider in providers {
                    let image = try await CodexAttachmentImporter.image(from: provider)
                    try store.addImage(image, for: originalTarget)
                }
            } catch { session.draftError = error.localizedDescription }
        }
    }

    private func send() {
        InteractionDiagnostics.shared.record(.composerSendBegin, flags: [.composerCanSubmit: canSubmit])
        defer { InteractionDiagnostics.shared.record(.composerSendEnd) }
        guard canSubmit else { return }
        InteractionDiagnostics.shared.record(.composerSendAccepted)
        store.setReadingPosition(nil, atBottom: true, for: target)
        Task { await store.sendDraft(to: target, modelSettings: modelSettings) }
    }
}

private struct CodexDraftThumbnail: View {
    let attachment: CodexDraftAttachment
    let target: CodexChatTarget
    let store: CodexConversationStore
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
        .frame(width: 76, height: 68)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel(attachment.name)
        .accessibilityIdentifier("chat.draftAttachment.\(attachment.id)")
        .task(id: attachment.id) {
            if let data = try? await store.imageData(attachment.messageAttachment, for: target) {
                InteractionDiagnostics.shared.record(.draftImageDecodeBegin)
                let decoded = UIImage(data: data)
                InteractionDiagnostics.shared.record(.draftImageDecodeEnd)
                InteractionDiagnostics.shared.record(.draftImagePublishBegin, geometry: decoded.map { [
                    .draftImageSize: [Double($0.size.width), Double($0.size.height)]
                ] } ?? [:])
                image = decoded
                InteractionDiagnostics.shared.record(.draftImagePublishEnd)
            }
        }
    }
}
