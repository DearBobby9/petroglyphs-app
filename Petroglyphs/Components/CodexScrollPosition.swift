import SwiftUI
import UIKit

struct CodexReadingBlockKey: PreferenceKey {
    static var defaultValue: [String: CodexReadingBlock] = [:]
    static func reduce(value: inout [String: CodexReadingBlock], nextValue: () -> [String: CodexReadingBlock]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

@MainActor
final class CodexScrollHandle {
    weak var scrollView: UIScrollView?

    func restore(frame: CGRect, fraction: Double) {
        guard let scrollView else { return }
        InteractionDiagnostics.shared.record(.chatNativeScrollBegin)
        defer { InteractionDiagnostics.shared.record(.chatNativeScrollEnd) }
        let desired = scrollView.contentOffset.y + frame.minY + frame.height * CGFloat(fraction)
        let lower = -scrollView.adjustedContentInset.top
        let upper = max(lower, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: min(upper, max(lower, desired))), animated: false)
    }
}

struct CodexScrollCapture: UIViewRepresentable {
    let handle: CodexScrollHandle
    func makeUIView(context: Context) -> UIView { UIView(frame: .zero) }
    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async { [weak view, weak handle] in
            InteractionDiagnostics.shared.record(.chatScrollCaptureBegin)
            defer { InteractionDiagnostics.shared.record(.chatScrollCaptureEnd) }
            var ancestor = view?.superview
            while let current = ancestor {
                if let scrollView = current as? UIScrollView { handle?.scrollView = scrollView; return }
                ancestor = current.superview
            }
        }
    }
}
