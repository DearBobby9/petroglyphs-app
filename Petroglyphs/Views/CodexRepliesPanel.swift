import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct CodexRepliesPanel: View {
    let store: CodexConversationStore
    let target: CodexChatTarget?
    let compactHeight: CGFloat?
    @Binding var isExpanded: Bool
    var isFocused = false
    var canSend = true
    let onChooseChat: () -> Void
    let onAddCanvas: () -> Data?
    let onComposerFocusChanged: (Bool) -> Void
    var onExpand: (() -> Void)? = nil
    var layoutControls: CanvasChatLayoutControls? = nil
    var keepsContentsMounted = false
    var onToggleExpanded: (() -> Void)? = nil

    private var session: CodexConversationSession? { target.map { store.session(for: $0) } }
    private var showsContents: Bool { isExpanded || keepsContentsMounted }

    var body: some View {
        VStack(spacing: 0) {
            if compactHeight == nil && !showsContents {
                collapsedSidebar
            } else {
                header
                if showsContents {
                    Divider()
                    if let target, let session {
                        chatContents(target: target, session: session)
                            .id(session.key)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right").font(.largeTitle)
                            Text("Choose a chat").font(.headline)
                            Text("Continue a conversation with text, pictures, and your canvas.")
                                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Choose a Codex chat", action: onChooseChat)
                                .buttonStyle(.borderedProminent).tint(Color.ochre).foregroundStyle(Color.onAccent)
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("chat.destination")
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(height: showsContents ? compactHeight : nil)
        .frame(maxHeight: showsContents && compactHeight == nil ? .infinity : nil)
        .foregroundStyle(Color.charcoal)
        .background(Color.panelBackground, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("codex.repliesPanel")
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button(action: toggleExpanded) {
                HStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                    Text("Chat").font(.headline)
                    if session?.isBusy == true { ProgressView().controlSize(.small) }
                    Spacer(minLength: 0)
                    Image(systemName: compactHeight == nil ? (layoutControls?.side == .left ? "chevron.left" : "chevron.right") : (isExpanded ? "chevron.down" : "chevron.up"))
                        .font(.caption.weight(.semibold))
                }
                .padding(.leading, 14)
                .padding(.trailing, 10)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse chat" : "Show chat")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityIdentifier("canvas.repliesToggle")
            if showsContents, let layoutControls {
                CanvasChatLayoutMenu(controls: layoutControls)
            }
            if showsContents, let onExpand {
                Button(action: onExpand) {
                    Image(systemName: isFocused ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isFocused ? "Return to canvas" : "Expand chat")
                .accessibilityIdentifier("chat.expand")
            }
            Button {
                if let target { Task { await store.refresh(for: target) } }
            } label: {
                Image(systemName: "arrow.clockwise").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(target == nil || session?.isRefreshing == true)
            .accessibilityLabel("Refresh conversation")
            .accessibilityHint("Loads this chat without sending another message.")
            .accessibilityIdentifier("codex.refreshReplies")
            .padding(.trailing, 4)
        }
    }

    private var collapsedSidebar: some View {
        Button(action: toggleExpanded) {
            VStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right").font(.body.weight(.semibold))
                if session?.isBusy == true { ProgressView().controlSize(.small) }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show chat")
        .accessibilityValue("Collapsed")
        .accessibilityIdentifier("canvas.repliesToggle")
    }

    private func toggleExpanded() {
        if let onToggleExpanded { onToggleExpanded(); return }
        if isExpanded { onComposerFocusChanged(false) }
        withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
    }

    private func chatContents(target: CodexChatTarget, session: CodexConversationSession) -> some View {
        VStack(spacing: 0) {
            Button(action: onChooseChat) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(target.thread.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Label(target.host.name, systemImage: target.host.kind == "remote" ? "network" : "desktopcomputer")
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

            if let error = session.error {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).font(.caption).textSelection(.enabled)
                }
                .foregroundStyle(Color.rust)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .accessibilityIdentifier("chat.loadError")
            }
            Divider()
            CodexConversationTimeline(store: store, target: target, session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            CodexMessageComposer(store: store, target: target, session: session,
                                 canSend: canSend, onAddCanvas: onAddCanvas,
                                 onFocusChanged: onComposerFocusChanged)
        }
    }
}

private struct CodexConversationTimeline: View {
    let store: CodexConversationStore
    let target: CodexChatTarget
    let session: CodexConversationSession
    @State private var restoredPosition = false
    @State private var userIsScrolling = false
    @State private var bottomY: CGFloat = 0
    @State private var rowPositions: [String: CGFloat] = [:]
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
                                let anchor = firstVisibleID ?? session.messages.first?.displayID
                                Task {
                                    await store.loadOlder(for: target)
                                    if let anchor { proxy.scrollTo(anchor, anchor: .top) }
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
                        ForEach(session.messages, id: \.displayID) { message in
                            CodexMessageRow(message: message, target: target, store: store)
                                .id(message.displayID)
                                .background(GeometryReader { row in
                                    Color.clear.preference(key: MessagePositionKey.self, value: [message.displayID: row.frame(in: .named("conversation-scroll")).minY])
                                })
                        }
                        if session.runState == "running" || session.runState == "waiting" {
                            Label(session.runState == "waiting" ? "Codex is waiting" : "Codex is working…", systemImage: "ellipsis.bubble")
                                .font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("chat.runState")
                        }
                        Color.clear.frame(height: 1).id(bottomID)
                            .background(GeometryReader { bottom in
                                Color.clear.preference(key: ConversationBottomKey.self, value: bottom.frame(in: .named("conversation-scroll")).maxY)
                            })
                    }
                    .padding(14)
                }
                .coordinateSpace(name: "conversation-scroll")
                .scrollDismissesKeyboard(.interactively)
                .accessibilityIdentifier("codex.repliesList")
                .onPreferenceChange(MessagePositionKey.self) { rowPositions = $0 }
                .onPreferenceChange(ConversationBottomKey.self) { position in
                    bottomY = position
                    let atBottom = position <= geometry.size.height + 60
                    if atBottom {
                        session.isAtBottom = true
                        hasNewMessages = false
                    } else if userIsScrolling { session.isAtBottom = false }
                }
                .simultaneousGesture(DragGesture(minimumDistance: 3).onChanged { _ in
                    userIsScrolling = true
                }.onEnded { _ in
                    let atBottom = bottomY <= geometry.size.height + 60
                    store.setReadingPosition(firstVisibleID, atBottom: atBottom, for: target)
                    userIsScrolling = false
                })
                .onChange(of: revision, initial: true) { _, _ in
                    guard !session.messages.isEmpty else { return }
                    if !restoredPosition {
                        restoredPosition = true
                        if !session.isAtBottom, let id = session.readingMessageID,
                           session.messages.contains(where: { $0.displayID == id }) {
                            proxy.scrollTo(id, anchor: .top)
                        } else { proxy.scrollTo(bottomID, anchor: .bottom) }
                    } else if session.isAtBottom && !userIsScrolling {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    } else { hasNewMessages = true }
                }
                .task(id: geometry.size) {
                    let wasFollowingLatest = session.isAtBottom
                    let readingAnchor = session.readingMessageID ?? firstVisibleID
                    // Width changes reflow message heights too. Restore after the new
                    // layout rather than using the lazy stack's previous measurements.
                    await Task.yield()
                    guard !Task.isCancelled, !userIsScrolling else { return }
                    if wasFollowingLatest && session.isAtBottom {
                        proxy.scrollTo(bottomID, anchor: .bottom)
                    } else if !wasFollowingLatest, let readingAnchor {
                        proxy.scrollTo(readingAnchor, anchor: .top)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !session.isAtBottom {
                        Button {
                            session.isAtBottom = true
                            hasNewMessages = false
                            store.setReadingPosition(nil, atBottom: true, for: target)
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(bottomID, anchor: .bottom) }
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

    private var firstVisibleID: String? {
        rowPositions.filter { $0.value >= -20 }.min { $0.value < $1.value }?.key
    }
}

private struct MessagePositionKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
private struct ConversationBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct CodexMessageComposer: View {
    let store: CodexConversationStore
    let target: CodexChatTarget
    let session: CodexConversationSession
    let canSend: Bool
    let onAddCanvas: () -> Data?
    let onFocusChanged: (Bool) -> Void
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var isDropTarget = false

    private var canSubmit: Bool {
        canSend && !session.draft.isEmpty && session.importingCount == 0 && session.draft.text.utf16.count <= 20_000
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !session.draft.attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(session.draft.attachments) { attachment in
                            VStack(spacing: 2) {
                                CodexDraftThumbnail(attachment: attachment, target: target, store: store)
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
            if session.importingCount > 0 {
                ProgressView("Adding image…").font(.caption)
            }
            HStack(alignment: .bottom, spacing: 6) {
                attachmentMenu
                ZStack(alignment: .topLeading) {
                    if session.draft.text.isEmpty {
                        Text("Message Codex…").foregroundStyle(.secondary).padding(.top, 10).padding(.leading, 3)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    CodexComposerInput(text: Binding(get: { session.draft.text }, set: { store.setDraftText($0, for: target) }),
                                       enabled: true, onFocusChanged: onFocusChanged,
                                       onPasteImages: importProviders, onSubmit: send)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                        .foregroundStyle(canSubmit ? Color.onAccent : Color.charcoal.opacity(0.35))
                        .background(canSubmit ? Color.ochre : Color.sandstone.opacity(0.4), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .accessibilityLabel(session.isBusy ? "Queue message" : "Send message")
                .accessibilityHint(session.isBusy ? "Sends to this chat after its current turn finishes." : "Sends text and attached images to the selected chat.")
                .accessibilityIdentifier("chat.send")
            }
            .padding(6)
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(isDropTarget ? Color.ochre : Color.charcoal.opacity(0.12), lineWidth: isDropTarget ? 2 : 1))
            .onDrop(of: [UTType.image], isTargeted: $isDropTarget) { providers in
                importProviders(providers)
                return !providers.isEmpty
            }
            if !canSend {
                Text("Reconnect to your Mac to send. Your draft is saved.").font(.caption).foregroundStyle(.secondary)
            } else if session.isBusy {
                Text("Your next message will wait for the current turn.").font(.caption).foregroundStyle(.secondary)
            }
            if session.draft.text.utf16.count > 20_000 {
                Text("Message is over the 20,000-character limit.").font(.caption).foregroundStyle(Color.rust)
            }
        }
        .padding(12)
        .background(Color.panelBackground)
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
                do { try store.addImage(CodexImportedImage(data: data, name: "Canvas.png", mimeType: "image/png"), for: target) }
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
        guard canSubmit else { return }
        store.setReadingPosition(nil, atBottom: true, for: target)
        Task { await store.sendDraft(to: target) }
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
            if let data = try? await store.imageData(attachment.messageAttachment, for: target) { image = UIImage(data: data) }
        }
    }
}
