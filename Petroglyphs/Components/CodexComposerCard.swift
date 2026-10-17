import SwiftUI

struct CodexComposerCard<AttachmentControl: View>: View {
    @Binding var text: String
    let canSubmit: Bool
    var isEditable = true
    var isDropTarget = false
    var isNewChat = false
    var hasImages = false
    let sendLabel: String
    let sendHint: String
    let modelSettings: CodexModelSettingsModel
    let modelSelection: CodexDraftModelSelection?
    let onModelSelectionChange: (CodexDraftModelSelection?) -> Void
    let onRefreshModels: () -> Void
    let onFocusChanged: (Bool) -> Void
    let onPasteImages: ([NSItemProvider]) -> Void
    let onSubmit: () -> Void
    @ViewBuilder let attachmentControl: AttachmentControl

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom, spacing: 6) {
                attachmentControl
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(isNewChat ? "Write the first message…" : "Message Codex…")
                            .foregroundStyle(.secondary).padding(.top, 10).padding(.leading, 3)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    CodexComposerInput(text: $text, enabled: isEditable, onFocusChanged: onFocusChanged,
                                       onPasteImages: onPasteImages, onSubmit: onSubmit)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(action: onSubmit) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                        .foregroundStyle(canSubmit ? Color.onAccent : Color.charcoal.opacity(0.35))
                        .background(canSubmit ? Color.ochre : Color.sandstone.opacity(0.4), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .accessibilityLabel(sendLabel)
                .accessibilityHint(sendHint)
                .accessibilityIdentifier("chat.send")
            }
            CodexModelControls(model: modelSettings, selection: modelSelection,
                               isNewChat: isNewChat, isLocked: !isEditable, hasImages: hasImages,
                               onChange: onModelSelectionChange, onRefresh: onRefreshModels)
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
        }
        .padding(6)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(isDropTarget ? Color.ochre : Color.charcoal.opacity(0.12), lineWidth: isDropTarget ? 2 : 1))
    }
}
