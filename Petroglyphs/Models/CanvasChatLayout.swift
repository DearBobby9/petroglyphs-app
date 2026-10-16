import SwiftUI

enum CanvasChatSide: String, CaseIterable {
    case left, right
}

/// The same canvas, separator, and chat remain mounted in this order in every mode.
/// Positioning them instead of rebuilding/reordering the view tree preserves PencilKit.
struct CanvasChatLayout: Layout {
    let mode: CanvasChatLayoutMode
    let side: CanvasChatSide
    /// Distance from the chat's outside edge to the middle of the gap, on either axis.
    /// Zero and the full axis length are the collapsed endpoints of the same layout.
    var chatExtent: CGFloat

    var animatableData: CGFloat {
        get { chatExtent }
        set { chatExtent = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let frames = CanvasChatFrames(size: bounds.size, mode: mode, side: side, chatExtent: chatExtent)
        let placements = [frames.canvas, frames.divider, frames.chat]
        for (index, subview) in subviews.enumerated() where index < placements.count {
            let frame = placements[index]
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}

enum CanvasChatLayoutMode {
    case canvasOnly, sideBySide, stacked
}

struct CanvasChatFrames {
    static let defaultChatFraction = 0.36
    static let minimumCanvasWidth: CGFloat = 360
    static let minimumChatWidth: CGFloat = 320
    static let dividerWidth: CGFloat = 8
    static let dividerHitWidth: CGFloat = 44
    static let stackedSpacing: CGFloat = 12

    let canvas: CGRect
    let divider: CGRect
    let chat: CGRect

    static func supportsSideBySide(in size: CGSize, accessibilityText: Bool) -> Bool {
        size.width >= 1_040 && size.width > size.height && !accessibilityText
    }

    static func chatFraction(_ requested: Double, availableWidth: CGFloat) -> Double {
        let contentWidth = max(0, availableWidth - dividerWidth)
        guard contentWidth >= minimumCanvasWidth + minimumChatWidth else { return defaultChatFraction }
        let requested = requested.isFinite ? requested : defaultChatFraction
        return min(max(requested, Double(minimumChatWidth / contentWidth)), Double(1 - minimumCanvasWidth / contentWidth))
    }

    /// Distance from the chat's outside edge to the center of the separator.
    /// Both closed endpoints are representable without leaving an empty separator.
    static func chatExtent(fraction: Double, availableWidth: CGFloat) -> CGFloat {
        let contentWidth = max(0, availableWidth - dividerWidth)
        return contentWidth * chatFraction(fraction, availableWidth: availableWidth) + dividerWidth / 2
    }

    static func chatFraction(extent: CGFloat, availableWidth: CGFloat) -> Double {
        chatFraction(Double((extent - dividerWidth / 2) / max(1, availableWidth - dividerWidth)),
                     availableWidth: availableWidth)
    }

    static func chatExtent(dividerCenter: CGFloat, side: CanvasChatSide, availableWidth: CGFloat) -> CGFloat {
        side == .left ? dividerCenter : availableWidth - dividerCenter
    }

    static func extentChange(translation: CGFloat, side: CanvasChatSide) -> CGFloat {
        side == .left ? translation : -translation
    }

    static func preferredStackedHeight(in availableHeight: CGFloat) -> CGFloat {
        min(min(520, max(300, availableHeight * 0.43)), max(0, availableHeight - 160 - stackedSpacing))
    }

    init(size: CGSize, mode: CanvasChatLayoutMode, side: CanvasChatSide, chatExtent: CGFloat) {
        let width = max(0, size.width)
        let height = max(0, size.height)
        let proposedExtent = chatExtent.isFinite ? chatExtent : 0
        switch mode {
        case .canvasOnly:
            canvas = CGRect(x: 0, y: 0, width: width, height: height)
            divider = .zero
            chat = .zero
        case .sideBySide:
            let extent = min(width, max(0, proposedExtent))
            let gap = min(Self.dividerWidth, 2 * min(extent, width - extent))
            let chatWidth = max(0, extent - gap / 2)
            let canvasWidth = max(0, width - extent - gap / 2)
            canvas = CGRect(x: side == .left ? chatWidth + gap : 0, y: 0, width: canvasWidth, height: height)
            let center = side == .left ? extent : width - extent
            divider = extent > 0 && extent < width
                ? CGRect(x: center - Self.dividerHitWidth / 2, y: 0, width: Self.dividerHitWidth, height: height)
                : .zero
            chat = CGRect(x: side == .left ? 0 : canvasWidth + gap, y: 0, width: chatWidth, height: height)
        case .stacked:
            let extent = min(height, max(0, proposedExtent))
            let gap = min(Self.stackedSpacing, 2 * min(extent, height - extent))
            let chatHeight = max(0, extent - gap / 2)
            let canvasHeight = max(0, height - extent - gap / 2)
            canvas = CGRect(x: 0, y: 0, width: width, height: canvasHeight)
            divider = .zero
            chat = CGRect(x: 0, y: canvasHeight + gap, width: width, height: chatHeight)
        }
    }
}

enum CanvasChatResizeDestination: Equatable {
    case split(Double)
    case hideChat
    case hideCanvas
}

struct CanvasChatResizeDecision {
    static let collapseThreshold: CGFloat = 96
    static let maximumProjection: CGFloat = 80

    let destination: CanvasChatResizeDestination
    let extent: CGFloat

    init(extent: CGFloat, velocity: CGFloat, availableWidth: CGFloat) {
        let width = max(0, availableWidth)
        let current = min(width, max(0, extent.isFinite ? extent : 0))
        let velocity = velocity.isFinite ? velocity : 0
        let projection = min(Self.maximumProjection, max(-Self.maximumProjection, velocity * 0.12))
        let projected = current + projection
        // Momentum can finish an edge gesture, but cannot collapse a usable panel
        // from an ordinary resize in the middle of the workspace.
        if current < CanvasChatFrames.minimumChatWidth && projected <= Self.collapseThreshold {
            destination = .hideChat
            self.extent = 0
        } else if width - current < CanvasChatFrames.minimumCanvasWidth && projected >= width - Self.collapseThreshold {
            destination = .hideCanvas
            self.extent = width
        } else {
            let fraction = CanvasChatFrames.chatFraction(extent: current, availableWidth: width)
            destination = .split(fraction)
            self.extent = CanvasChatFrames.chatExtent(fraction: fraction, availableWidth: width)
        }
    }
}
