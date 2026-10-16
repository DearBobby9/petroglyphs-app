import SwiftUI

struct CanvasChatLayoutControls {
    let side: CanvasChatSide
    let chatFraction: Double
    let canResize: Bool
    let canNarrow: Bool
    let canWiden: Bool
    let setSide: (CanvasChatSide) -> Void
    let adjustWidth: (Double) -> Void
    let resetWidth: () -> Void
}

struct CanvasChatLayoutMenu: View {
    let controls: CanvasChatLayoutControls

    var body: some View {
        Menu {
            Section("Chat position") {
                ForEach(CanvasChatSide.allCases, id: \.rawValue) { side in
                    Button {
                        controls.setSide(side)
                    } label: {
                        Label(side == .left ? "Chat on left" : "Chat on right",
                              systemImage: controls.side == side ? "checkmark" : (side == .left ? "sidebar.left" : "sidebar.right"))
                    }
                    .accessibilityAddTraits(controls.side == side ? .isSelected : [])
                    .accessibilityIdentifier("chat.layout.\(side.rawValue)")
                }
            }
            Section("Chat width") {
                Button("Narrower chat", systemImage: "minus") { controls.adjustWidth(-0.05) }
                    .disabled(!controls.canResize || !controls.canNarrow)
                    .accessibilityIdentifier("chat.layout.narrower")
                Button("Wider chat", systemImage: "plus") { controls.adjustWidth(0.05) }
                    .disabled(!controls.canResize || !controls.canWiden)
                    .accessibilityIdentifier("chat.layout.wider")
                Button("Reset width", systemImage: "arrow.counterclockwise") { controls.resetWidth() }
                    .accessibilityIdentifier("chat.layout.reset")
            }
            if !controls.canResize {
                Text("Position and width apply when the canvas and chat are side by side.")
            }
        } label: {
            Image(systemName: "rectangle.split.2x1")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Chat layout")
        .accessibilityValue("\(controls.side == .left ? "Left" : "Right"), \(Int((controls.chatFraction * 100).rounded())) percent")
        .accessibilityIdentifier("chat.layoutMenu")
    }
}

struct CanvasChatDivider: View {
    let controls: CanvasChatLayoutControls
    let availableWidth: CGFloat
    let isEnabled: Bool
    let onResize: (CGFloat) -> Void
    let onResizeEnded: (CGFloat, CGFloat) -> Void
    let onResizeCancelled: () -> Void
    let onHideChat: () -> Void
    let onHideCanvas: () -> Void
    @GestureState private var gestureIsActive = false
    @State private var dragOrigin: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle()
                    .fill(Color.charcoal.opacity(0.10))
                    .frame(width: 1)
                    .padding(.vertical, 24)
                Capsule()
                    .fill(dragOrigin == nil ? Color.charcoal.opacity(0.45) : Color.ochre)
                    .frame(width: 3, height: dragOrigin == nil ? 28 : 40)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("canvas-chat-workspace"))
                .updating($gestureIsActive) { _, active, _ in active = true }
                .onChanged { value in
                    guard isEnabled else { return }
                    if dragOrigin == nil {
                        // Read the displayed separator, not its spring's target. A new
                        // drag can take over a settling or closing panel without a jump.
                        dragOrigin = CanvasChatFrames.chatExtent(
                            dividerCenter: geometry.frame(in: .named("canvas-chat-workspace")).midX,
                            side: controls.side, availableWidth: availableWidth
                        )
                    }
                    onResize(extent(for: value.translation.width))
                }
                .onEnded { value in
                    guard isEnabled, dragOrigin != nil else { cancelResize(); return }
                    let extent = extent(for: value.translation.width)
                    let velocity = CanvasChatFrames.extentChange(translation: value.velocity.width, side: controls.side)
                    dragOrigin = nil
                    onResizeEnded(extent, velocity)
                }
            )
        }
        .clipped()
        .onChange(of: gestureIsActive) { _, active in if !active { cancelResize() } }
        .onChange(of: isEnabled) { _, _ in cancelResize() }
        .onChange(of: availableWidth) { _, _ in cancelResize() }
        .onChange(of: controls.side) { _, _ in cancelResize() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chat width")
        .accessibilityValue("\(Int((controls.chatFraction * 100).rounded())) percent")
        .accessibilityHint("Drag toward either edge to hide that panel. Adjust up or down to resize the chat.")
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: controls.adjustWidth(0.05)
            case .decrement: controls.adjustWidth(-0.05)
            @unknown default: break
            }
        }
        .accessibilityAction(named: "Reset width") { controls.resetWidth() }
        .accessibilityAction(named: "Hide chat") { onHideChat() }
        .accessibilityAction(named: "Hide canvas") { onHideCanvas() }
        .accessibilityIdentifier("canvas.chatDivider")
    }

    private func extent(for translation: CGFloat) -> CGFloat {
        let origin = dragOrigin ?? CanvasChatFrames.chatExtent(fraction: controls.chatFraction, availableWidth: availableWidth)
        return min(availableWidth, max(0, origin + CanvasChatFrames.extentChange(translation: translation, side: controls.side)))
    }

    private func cancelResize() {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        onResizeCancelled()
    }
}

/// Keep content readable while an edge gesture reveals or clips it below its
/// usable width. The content stays mounted through both collapsed endpoints.
struct CanvasChatPane<Content: View>: View {
    let minimumWidth: CGFloat
    let alignment: Alignment
    @ViewBuilder let content: Content

    var body: some View {
        CanvasChatPaneLayout(minimumWidth: minimumWidth, alignment: alignment) {
            content
        }
        .clipped()
    }
}

private struct CanvasChatPaneLayout: Layout {
    let minimumWidth: CGFloat
    let alignment: Alignment

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let content = subviews.first?.sizeThatFits(proposal) ?? .zero
        return CGSize(width: proposal.width ?? content.width, height: proposal.height ?? content.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let contentWidth = max(minimumWidth, bounds.width)
        let x = alignment == .trailing ? bounds.maxX - contentWidth : bounds.minX
        subviews.first?.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                              proposal: ProposedViewSize(width: contentWidth, height: bounds.height))
    }
}
