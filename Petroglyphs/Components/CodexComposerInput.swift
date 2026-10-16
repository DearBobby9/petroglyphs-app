import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CodexComposerInput: UIViewRepresentable {
    @Binding var text: String
    let enabled: Bool
    let onFocusChanged: (Bool) -> Void
    let onPasteImages: ([NSItemProvider]) -> Void
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> ImagePastingTextView {
        let view = ImagePastingTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = .label
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 10, left: 3, bottom: 10, right: 3)
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.keyboardDismissMode = .interactive
        view.accessibilityLabel = "Message Codex"
        view.accessibilityIdentifier = "chat.composer"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: ImagePastingTextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text && view.markedTextRange == nil { view.text = text }
        view.isEditable = enabled
        view.onPasteImages = onPasteImages
        view.onSubmit = onSubmit
        if !enabled && view.isFirstResponder { view.resignFirstResponder() }
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ImagePastingTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let desired = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        let maximum = UIFont.preferredFont(forTextStyle: .body).lineHeight * 5 + 20
        let height = min(max(44, desired), maximum)
        uiView.isScrollEnabled = desired > maximum
        return CGSize(width: width, height: height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    static func dismantleUIView(_ uiView: ImagePastingTextView, coordinator: Coordinator) {
        if uiView.isFirstResponder { uiView.resignFirstResponder() }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodexComposerInput
        init(_ parent: CodexComposerInput) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            textView.invalidateIntrinsicContentSize()
        }
        func textViewDidBeginEditing(_ textView: UITextView) { parent.onFocusChanged(true) }
        func textViewDidEndEditing(_ textView: UITextView) { parent.onFocusChanged(false) }
    }
}

final class ImagePastingTextView: UITextView {
    var onPasteImages: (([NSItemProvider]) -> Void)?
    var onSubmit: (() -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        (super.keyCommands ?? []) + [UIKeyCommand(title: "Send message", action: #selector(sendFromKeyboard), input: "\r", modifierFlags: .command)]
    }

    @objc private func sendFromKeyboard() {
        // Return alone inserts a newline. Do not submit an unfinished IME composition.
        guard markedTextRange == nil, isEditable else { return }
        onSubmit?()
    }

    override func paste(_ sender: Any?) {
        guard isEditable else { return }
        // Read actual clipboard contents only in response to the user's Paste / Cmd-V.
        if UIPasteboard.general.hasImages {
            let providers = UIPasteboard.general.itemProviders.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
            if !providers.isEmpty { onPasteImages?(providers); return }
        }
        super.paste(sender)
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)), isEditable, UIPasteboard.general.hasImages { return true }
        return super.canPerformAction(action, withSender: sender)
    }
}
