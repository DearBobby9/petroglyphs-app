import SwiftUI

struct CodexChatChromeHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

extension View {
    func chatChromeHeight(_ part: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: CodexChatChromeHeightKey.self, value: [part: geometry.size.height])
        })
    }
}

private struct CodexComposerHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 260
}

extension EnvironmentValues {
    var codexComposerMaximumHeight: CGFloat {
        get { self[CodexComposerHeightKey.self] }
        set { self[CodexComposerHeightKey.self] = newValue }
    }
}

private struct CodexComposerContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct CodexComposerScroll<Content: View>: View {
    let maximumHeight: CGFloat
    @ViewBuilder let content: Content
    @State private var contentHeight: CGFloat = 120

    var body: some View {
        ScrollView(.vertical) {
            content
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: CodexComposerContentHeightKey.self, value: geometry.size.height)
                })
        }
        .frame(height: min(maximumHeight, max(44, contentHeight)))
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(CodexComposerContentHeightKey.self) { contentHeight = $0 }
    }
}
