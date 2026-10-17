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
                            CodexMessageImage(attachment: attachment, target: target, store: store)
                        }
                    }
                }
                if !message.text.isEmpty {
                    if isUser {
                        Text(message.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        CodexMarkdownText(text: message.text)
                    }
                }
            }
            .padding(isUser ? 12 : 0)
            .background(isUser ? Color.sandstone : Color.clear, in: RoundedRectangle(cornerRadius: 16))
            .frame(maxWidth: .infinity, alignment: .leading)

            if isUser {
                HStack(spacing: 5) {
                    if !message.state.isTerminal { ProgressView().controlSize(.mini) }
                    if message.state == .failed { Image(systemName: "exclamationmark.circle") }
                    Text(message.state.label)
                        .accessibilityIdentifier("chat.status.\(message.clientMessageId ?? message.id)")
                    if let date = message.createdAt { Text(date, style: .time) }
                }
                .font(.caption)
                .foregroundStyle(message.state == .failed ? Color.rust : Color.charcoal.opacity(0.65))
                if let selection = receipt?.selection ?? local?.selection {
                    CodexModelEvidenceView(selection: selection, evidence: receipt?.modelEvidence,
                                           verification: receipt?.modelVerification)
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
    let attachment: CodexConversationAttachment
    let target: CodexChatTarget
    let store: CodexConversationStore
    @State private var image: UIImage?
    @State private var error: String?
    @State private var showPreview = false
    @State private var retryID = 0

    var body: some View {
        Group {
            if let image {
                Button { showPreview = true } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open image: \(attachment.name)")
            } else if attachment.availability != "available" {
                imagePlaceholder("Image unavailable", detail: "This older image cannot be retrieved.")
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
        .task(id: "\(CodexConversationKey(target).storageID):\(attachment.id):\(retryID)") {
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
            NavigationStack {
                Group {
                    if let image { Image(uiImage: image).resizable().scaledToFit().padding() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.panelBackground)
                .navigationTitle(attachment.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPreview = false } } }
            }
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

private struct CodexMarkdownText: View {
    let text: String
    private var blocks: [Block] { Block.parse(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                if block.isCode {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text(block.language.isEmpty ? "Code" : block.language).font(.caption)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = block.text
                            } label: { Label("Copy", systemImage: "doc.on.doc").font(.caption).frame(minHeight: 44) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Copy code")
                        }
                        .padding(.horizontal, 10)
                        ScrollView(.horizontal) {
                            Text(block.text)
                                .font(.system(.callout, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(10)
                        }
                    }
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Text((try? AttributedString(markdown: block.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(block.text))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct Block {
        let text: String
        let isCode: Bool
        let language: String
        static func parse(_ text: String) -> [Block] {
            var blocks: [Block] = []
            var lines: [String] = []
            var isCode = false
            var language = ""
            for line in text.components(separatedBy: "\n") {
                if line.hasPrefix("```") {
                    if !lines.isEmpty { blocks.append(Block(text: lines.joined(separator: "\n"), isCode: isCode, language: language)) }
                    lines = []
                    isCode.toggle()
                    language = isCode ? String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces) : ""
                } else { lines.append(line) }
            }
            if !lines.isEmpty { blocks.append(Block(text: lines.joined(separator: "\n"), isCode: isCode, language: language)) }
            return blocks
        }
    }
}
