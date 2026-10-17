import SwiftUI

struct CodexNewChatPanel: View {
    let model: CodexProjectCreationModel
    let modelSettings: CodexModelSettingsModel
    let isConnected: Bool
    let onCancel: () -> Void
    let onChooseDestination: () -> Void
    let onRefreshModels: () -> Void
    let onFocusChanged: (Bool) -> Void
    let onCreated: (CodexThread) -> Void
    @State private var attachmentNotice: String?

    private var canSubmit: Bool {
        isConnected && model.canSubmit
            && (model.modelSelection == nil || modelSettings.matches(from: model.serverURL, hostId: model.host.id, threadId: nil))
            && modelSettings.validationMessage(for: model.modelSelection) == nil
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
                            Text("Send a text message to create this chat. You can add drawings and images afterward.")
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
                    if let thread = model.recoverableThread {
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
            VStack(alignment: .leading, spacing: 8) {
                CodexComposerCard(text: $model.prompt, canSubmit: canSubmit, isEditable: model.request == nil,
                                  isNewChat: true, sendLabel: "Start chat",
                                  sendHint: "Creates this project chat and sends the first text message.",
                                  modelSettings: modelSettings, modelSelection: model.modelSelection,
                                  onModelSelectionChange: { model.modelSelection = $0 }, onRefreshModels: onRefreshModels,
                                  onFocusChanged: onFocusChanged, onPasteImages: { _ in showAttachmentNotice() }, onSubmit: submit) {
                    Button(action: showAttachmentNotice) {
                        Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle())
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(model.request != nil)
                    .accessibilityLabel("Attachments after the first message")
                    .accessibilityIdentifier("chat.addAttachment")
                }
                if let attachmentNotice { Text(attachmentNotice).font(.caption).foregroundStyle(.secondary) }
                if !isConnected { Text("Reconnect to your Mac to start this chat. Your draft is saved.").font(.caption).foregroundStyle(.secondary) }
                if model.title.utf16.count > 120 { Text("Use 120 characters or fewer for the name.").font(.caption).foregroundStyle(Color.rust) }
                if model.prompt.utf16.count > 20_000 { Text("Message is over the 20,000-character limit.").font(.caption).foregroundStyle(Color.rust) }
            }
            .padding(12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.newDraft")
        .onChange(of: modelSettings.isLoading, initial: true) { _, loading in
            if !loading { model.validateDestination(using: modelSettings) }
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

    private func showAttachmentNotice() {
        attachmentNotice = "Send the first text message, then add images or your canvas."
    }
}
