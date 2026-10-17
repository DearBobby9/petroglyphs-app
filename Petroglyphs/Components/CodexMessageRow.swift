import SwiftUI
import UIKit

struct CodexMessageRow: View {
    let message: CodexConversationMessage
    let target: CodexChatTarget
    let store: CodexConversationStore

    private var isUser: Bool { message.role == "user" }
    private var local: CodexLocalMessage? { store.localMessage(message.clientMessageId, for: target) }
    private var receipt: CodexMessageReceipt? { store.receipt(message.clientMessageId ?? message.id, for: target) }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            if !isUser {
                Text(message.phase == "commentary" ? "Codex · Progress" : "Codex")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                if !message.attachments.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: message.attachments.count > 1 ? 2 : 1), spacing: 8) {
                        ForEach(message.attachments) { attachment in
                            CodexMessageImage(attachment: attachment, siblings: message.attachments, target: target, store: store)
                        }
                    }
                }
                if let omittedCount = message.omittedResultImageCount, omittedCount > 0 {
                    Label(omittedCount == 1 ? "1 additional result image is not shown." : "\(omittedCount) additional result images are not shown.",
                          systemImage: "photo.stack")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("chat.omittedImages.\(message.displayID)")
                }
                if !message.text.isEmpty {
                    if isUser {
                        Text(message.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        CodexMarkdownText(text: message.text, messageID: message.displayID).equatable()
                    }
                }
            }
            .padding(isUser ? 12 : 0)
            .background(isUser ? Color.sandstone : Color.clear, in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: .infinity, alignment: .leading)

            if isUser {
                HStack(spacing: 5) {
                    if message.state == .dispatching { ProgressView().controlSize(.mini) }
                    if message.state == .pending { Image(systemName: "clock") }
                    if message.state == .failed { Image(systemName: "exclamationmark.circle") }
                    Text(message.deliveryLabel(receipt: receipt))
                        .accessibilityIdentifier("chat.status.\(message.clientMessageId ?? message.id)")
                    if let date = message.createdAt { Text(date, style: .time) }
                }
                .font(.caption)
                .foregroundStyle(message.state == .failed ? Color.rust : Color.charcoal.opacity(0.65))
                if let selection = receipt?.selection ?? local?.selection {
                    if receipt?.modelVerification == "different" {
                        Label("The actual model differs from the requested model", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(Color.rust)
                    }
                    DisclosureGroup("Model details") {
                        CodexModelEvidenceView(selection: selection, evidence: receipt?.modelEvidence,
                                               verification: receipt?.modelVerification)
                    }
                    .font(.caption)
                    .accessibilityIdentifier("chat.modelEvidence.\(message.clientMessageId ?? message.id)")
                }
                if let notice = local?.notice ?? receipt?.notice, !notice.isEmpty {
                    Text(notice).font(.caption).foregroundStyle(.secondary)
                }
                if let error = local?.error ?? receipt?.error, !error.isEmpty {
                    Text(error).font(.caption).foregroundStyle(Color.rust)
                }
                if local?.canRetry == true, let id = local?.id {
                    Button("Try sending again") { Task { await store.retryUnaccepted(id, for: target) } }
                        .font(.callout)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("chat.retry.\(id)")
                }
                if message.state == .unknown, let id = message.clientMessageId ?? receipt?.id {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message.uncertaintyNotice(receipt: receipt))
                            .font(.caption).foregroundStyle(.secondary)
                        if store.canReleaseWait(id, for: target) {
                            Button("Let later messages continue") { Task { await store.releaseWait(id, for: target) } }
                                .font(.callout).frame(minHeight: 44)
                                .accessibilityIdentifier("chat.releaseWait.\(id)")
                            Text("This keeps the original request. It does not resend the message or stop remote execution.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Request \(id)").font(.caption2.monospaced()).textSelection(.enabled)
                    }
                }
                if receipt?.state == .pending, let id = receipt?.id {
                    Button("Cancel queued message") { Task { await store.cancelPending(id, for: target) } }
                        .font(.callout).frame(minHeight: 44)
                        .accessibilityIdentifier("chat.cancelPending.\(id)")
                }
            } else if !message.text.isEmpty {
                Button {
                    UIPasteboard.general.string = message.text
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Copy Codex reply")
                .accessibilityIdentifier("chat.copy.\(message.displayID)")
            }
        }
        .font(.body)
        .padding(.leading, isUser ? 28 : 0)
        .padding(.trailing, isUser ? 0 : 12)
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("chat.message.\(message.displayID)")
        .contextMenu {
            if !message.text.isEmpty {
                Button("Copy text", systemImage: "doc.on.doc") { UIPasteboard.general.string = message.text }
            }
        }
    }
}

struct CodexMessageImage: View {
    @Environment(AppState.self) private var appState
    @AppStorage("codexRepliesExpanded") private var repliesExpanded = true
    @AppStorage("codexCanvasCollapsed") private var chatFocused = false
    let attachment: CodexConversationAttachment
    let siblings: [CodexConversationAttachment]
    let target: CodexChatTarget
    let store: CodexConversationStore
    @State private var image: UIImage?
    @State private var error: String?
    @State private var showPreview = false
    @State private var retryID = 0

    var body: some View {
        Group {
            if let reason = attachment.imageUnavailableMessage {
                imagePlaceholder("Image unavailable", detail: reason)
            } else if let image {
                Button { showPreview = true } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open image: \(attachment.name)")
            } else if error != nil {
                Button { retryID += 1 } label: {
                    imagePlaceholder("Image could not load", detail: "Tap to try again")
                }
                .buttonStyle(.plain)
            } else {
                ProgressView().frame(maxWidth: .infinity).frame(height: 140)
            }
        }
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("chat.attachment.\(attachment.id)")
        .task(id: "\(CodexConversationKey(target).storageID):\(attachment.id):\(attachment.availability):\(retryID)") {
            image = nil
            error = nil
            guard attachment.availability == "available" else { return }
            do {
                let data = try await store.imageData(attachment, for: target)
                guard !Task.isCancelled else { return }
                guard let decoded = UIImage(data: data) else { throw CodexConversationStore.ConversationError.imageUnavailable }
                image = decoded
                error = nil
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
        .sheet(isPresented: $showPreview) {
            CodexImagePreview(items: siblings.map { item in
                CodexImagePreviewItem(id: item.id, name: item.name, unavailableReason: item.imageUnavailableMessage,
                                      load: { try await store.imageData(item, for: target) })
            }, selectedID: attachment.id, onUseAsReference: { item, data in
                try appState.canvasViewModel.setReferenceImage(data: data, name: item.name,
                    sourceID: "chat:\(target.host.id):\(target.thread.id):attachment:\(item.id)")
                appState.selectedCodexChat = target
                appState.newCodexChat = nil
                chatFocused = false
                repliesExpanded = false
            })
        }
    }

    private func imagePlaceholder(_ title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "photo").font(.title2)
            Text(title).font(.caption.weight(.semibold))
            Text(detail).font(.caption2)
        }
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(8)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 140)
    }
}

private extension CodexConversationAttachment {
    var imageUnavailableMessage: String? {
        guard availability != "available" else { return nil }
        switch unavailableReason {
        case "remote_file_unsupported": return "This image is stored on the remote Mac and cannot be retrieved by this bridge."
        case "outside_workspace": return "This image is outside the folders available to this chat."
        case "unsupported_source": return "This image source is not supported. Import a PNG or JPEG from Files or Photos."
        case "invalid_image": return "The result is not a valid PNG or JPEG image."
        case "image_too_large": return "This image exceeds the 10 MB limit."
        case "image_missing": return "The original result image could not be found."
        case "snapshot_unavailable": return "A saved copy of this result image is unavailable."
        case "total_size_exceeded": return "The result images exceed the 24 MB limit for one message."
        default: return "This image cannot be retrieved."
        }
    }
}
