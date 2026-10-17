import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct CodexNewChatPanel: View {
    let model: CodexProjectCreationModel
    let modelSettings: CodexModelSettingsModel
    let isConnected: Bool
    let onCancel: () -> Void
    let onChooseDestination: () -> Void
    let onRefreshModels: () -> Void
    let onFocusChanged: (Bool) -> Void
    let onCreated: (CodexThread) -> Void
    let onAddCanvas: () -> Data?
    let onCanvasFilename: () -> String
    @Environment(\.codexComposerMaximumHeight) private var maximumComposerHeight
    @State private var attachmentNotice: String?
    @State private var isImporting = false
    @State private var showPhotos = false
    @State private var showFiles = false
    @State private var photos: [PhotosPickerItem] = []
    @State private var previewAttachment: CodexCreateChatAttachment?

    private var canSubmit: Bool {
        isConnected && model.canSubmit && !isImporting
            && (model.modelSelection == nil || modelSettings.matches(from: model.serverURL, hostId: model.host.id, threadId: nil))
            && modelSettings.validationMessage(for: model.modelSelection, hasImages: !model.attachments.isEmpty) == nil
    }

    private var attachmentUnavailableReason: String? {
        if model.request != nil { return "The first message has been submitted. Check its status before adding images." }
        if !model.project.supportsFirstMessageAttachments {
            return "This destination has not verified first-message image support. Choose another destination or start with text."
        }
        if model.attachments.count >= CodexAttachmentImporter.maximumCount {
            return "This message already has \(CodexAttachmentImporter.maximumCount) images. Remove an image before adding another."
        }
        if isImporting { return "Wait for the current images to finish importing." }
        return nil
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onChooseDestination) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("New chat").font(.subheadline.weight(.semibold))
                        Label("\(model.host.name) · \(model.project.displayName)", systemImage: "folder")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.request != nil)
                .accessibilityLabel("New chat destination: \(model.host.name), \(model.project.displayName)")
                .accessibilityIdentifier("chat.newDraftDestination")
                Button(action: onCancel) {
                    Image(systemName: "xmark").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.isSubmitting || model.isRetrying)
                .accessibilityLabel(model.request == nil ? "Cancel new chat" : "Return to previous chat")
                .accessibilityHint("Keeps this draft and any submitted creation request.")
                .accessibilityIdentifier("chat.cancelNewDraft")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.request == nil {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Start a new conversation").font(.headline)
                            Text("Create this chat with one complete message, including supported image attachments.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        DisclosureGroup("Chat name (optional)") {
                            TextField("Name", text: $model.title)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("codex.chatName")
                                .padding(.top, 8)
                        }
                        .font(.callout)
                    } else {
                        Text(model.request?.prompt ?? model.prompt)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.sandstone, in: RoundedRectangle(cornerRadius: 16))
                    }
                    if let status = model.status {
                        HStack(spacing: 10) {
                            if model.isBusy || model.isObservingCreation { ProgressView() }
                            Text(status).font(.callout)
                        }
                        .accessibilityIdentifier("codex.creationStatus")
                    }
                    if let notice = model.receipt?.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                    if model.receipt?.creationMethod != "native", let attempt = model.receipt?.attemptNumber {
                        Text("Creation attempt \(attempt) of 2").font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("codex.creationAttempt")
                    }
                    if let error = model.storageError ?? model.error {
                        Text(error).font(.callout).foregroundStyle(Color.rust)
                            .accessibilityIdentifier("codex.creationError")
                    }
                    if model.request != nil && model.createdThread == nil && !model.canEditFailedAttempt {
                        Button("Check status") { Task { await model.checkStatus() } }
                            .frame(minHeight: 44).disabled(model.isBusy)
                            .accessibilityIdentifier("codex.checkCreation")
                    }
                    if let thread = model.createdThread ?? model.recoverableThread {
                        Button("Open created chat") { onCreated(thread) }
                            .buttonStyle(.borderedProminent)
                            .frame(minHeight: 44)
                            .accessibilityHint("Opens the existing chat without creating another one or resending the first message.")
                            .accessibilityIdentifier("codex.openCreatedChat")
                    }
                    if model.canRetryOriginal {
                        Button("Retry this request") { Task { await model.retryOriginal() } }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("codex.retryCreation")
                    }
                    if model.canRetryCreation || model.isRetrying {
                        Button(model.isRetrying ? "Retrying creation…" : "Retry creation") { Task { await model.retryCreation() } }
                            .buttonStyle(.borderedProminent)
                            .frame(minHeight: 44)
                            .disabled(!model.canRetryCreation || !isConnected)
                            .accessibilityHint("Retries the original request once with the same project, first message, and model.")
                            .accessibilityIdentifier("codex.retryCreation")
                    }
                    if model.canEditFailedAttempt {
                        Button("Edit and try again") { model.editFailedAttempt() }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("codex.editFailedCreation")
                    }
                    if model.canStartNewRequest {
                        Button("Start a new request") { model.startNewRequest() }
                            .frame(minHeight: 44)
                            .accessibilityHint("Keeps the title, first message, and model for editing. Nothing is sent until you choose Start chat.")
                            .accessibilityIdentifier("codex.startNewCreationRequest")
                        Text("This opens an editable draft with the same message and model. Nothing is sent until you choose Start chat.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .frame(maxHeight: .infinity)
            Divider()
            CodexComposerScroll(maximumHeight: maximumComposerHeight) {
            VStack(alignment: .leading, spacing: 8) {
                if !model.attachments.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(model.attachments) { attachment in
                                VStack(spacing: 2) {
                                    Button { previewAttachment = attachment } label: {
                                        if let data = attachment.imageData, let image = UIImage(data: data) {
                                            Image(uiImage: image).resizable().scaledToFit().frame(width: 76, height: 68)
                                        }
                                    }
                                    .buttonStyle(.plain).accessibilityLabel("Preview \(attachment.name)")
                                    if model.request == nil {
                                        Button("Remove", systemImage: "xmark.circle") { model.removeAttachment(attachment.id) }
                                            .font(.caption).frame(minHeight: 44)
                                    }
                                }
                            }
                        }
                    }
                }
                if isImporting { Text("Adding image…").font(.caption).foregroundStyle(.secondary) }
                CodexComposerCard(text: $model.prompt, canSubmit: canSubmit, isEditable: model.request == nil,
                                  isNewChat: true, hasImages: !model.attachments.isEmpty, sendLabel: "Start chat",
                                  sendHint: "Creates this project chat and sends the complete first message.",
                                  modelSettings: modelSettings, modelSelection: model.modelSelection,
                                  onModelSelectionChange: { model.modelSelection = $0 }, onRefreshModels: onRefreshModels,
                                  onFocusChanged: onFocusChanged, onPasteImages: importProviders, onSubmit: submit) {
                    attachmentMenu
                }
                if model.request == nil, !isImporting, let reason = attachmentUnavailableReason {
                    Text(reason)
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let attachmentNotice { Text(attachmentNotice).font(.caption).foregroundStyle(.secondary) }
                if !isConnected { Text("Reconnect to your Mac to start this chat. Your draft is saved.").font(.caption).foregroundStyle(.secondary) }
                if model.title.utf16.count > 120 { Text("Use 120 characters or fewer for the name.").font(.caption).foregroundStyle(Color.rust) }
                if model.prompt.utf16.count > 20_000 { Text("Message is over the 20,000-character limit.").font(.caption).foregroundStyle(Color.rust) }
            }
            .padding(12)
            }
            .chatChromeHeight("composer")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.newDraft")
        .sheet(item: $previewAttachment) { attachment in
            CodexImagePreview(items: model.attachments.map { item in
                CodexImagePreviewItem(id: item.id, name: item.name, load: {
                    guard let data = item.imageData else { throw CodexConversationStore.ConversationError.imageUnavailable }
                    return data
                })
            }, selectedID: attachment.id, onRemove: model.request == nil ? { model.removeAttachment($0) } : nil)
        }
        .photosPicker(isPresented: $showPhotos, selection: $photos,
                      maxSelectionCount: max(1, CodexAttachmentImporter.maximumCount - model.attachments.count), matching: .images)
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            isImporting = true
            Task {
                defer { isImporting = false; photos = [] }
                do {
                    for item in items {
                        guard let data = try await item.loadTransferable(type: Data.self) else { throw CodexAttachmentImporter.ImportError.unsupported }
                        let image = try await Task.detached { try CodexAttachmentImporter.normalize(data, name: "Photo") }.value
                        try model.addImage(image)
                    }
                } catch { attachmentNotice = error.localizedDescription }
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            isImporting = true
            Task {
                defer { isImporting = false }
                do {
                    for url in try result.get() {
                        let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let data = try Data(contentsOf: url)
                        let image = try await Task.detached { try CodexAttachmentImporter.normalize(data, name: url.lastPathComponent) }.value
                        try model.addImage(image)
                    }
                } catch { attachmentNotice = error.localizedDescription }
            }
        }
        .onChange(of: modelSettings.isLoading, initial: true) { _, loading in
            if !loading { model.validateDestination(using: modelSettings) }
        }
        .onChange(of: model.attachments) { _, _ in
            model.validateDestination(using: modelSettings)
        }
        .onChange(of: model.modelSelection) { _, _ in model.validateDestination(using: modelSettings) }
        .task(id: "\(model.serverURL.absoluteString):\(model.host.id):\(model.project.id)") {
            model.validateDestination(using: modelSettings)
        }
        .task(id: model.statusObservationID) { await model.observeCreation() }
        .onChange(of: model.createdThread, initial: true) { _, thread in
            if let thread { onCreated(thread) }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        Task { await model.submit() }
    }

    private var attachmentMenu: some View {
        Menu {
            Button("Photos", systemImage: "photo") { showPhotos = true }
            Button("Choose image file", systemImage: "folder") { showFiles = true }
            Button("Add current canvas", systemImage: "pencil.tip.crop.circle.badge.plus") {
                if let reason = attachmentUnavailableReason { attachmentNotice = reason; return }
                guard let data = onAddCanvas() else { attachmentNotice = "Add content to the canvas first."; return }
                do {
                    try model.addImage(CodexImportedImage(data: data, name: onCanvasFilename(), mimeType: "image/png"))
                } catch { attachmentNotice = error.localizedDescription }
            }
            PasteButton(supportedContentTypes: [.image], payloadAction: importProviders)
        } label: {
            Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .disabled(attachmentUnavailableReason != nil)
        .accessibilityLabel("Add attachment")
        .accessibilityIdentifier("chat.addAttachment")
    }

    private func importProviders(_ providers: [NSItemProvider]) {
        if let reason = attachmentUnavailableReason { attachmentNotice = reason; return }
        isImporting = true
        Task {
            defer { isImporting = false }
            do {
                for provider in providers { try model.addImage(await CodexAttachmentImporter.image(from: provider)) }
            } catch { attachmentNotice = error.localizedDescription }
        }
    }
}
