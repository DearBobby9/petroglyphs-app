import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var viewModel: CanvasViewModel
    var isDrawingActive = true
    var isSelectingExportBounds = false
    var onExportBoundsSelected: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> CanvasDocumentSurface {
        InteractionDiagnostics.shared.startIfEnabled()
        InteractionDiagnostics.shared.record(.canvasMake)
        let surface = CanvasDocumentSurface()
        let canvas = surface.canvas
        surface.apply(viewModel, selecting: isSelectingExportBounds, onSelection: onExportBoundsSelected)
        context.coordinator.surface = surface
        canvas.viewModel = viewModel
        canvas.delegate = context.coordinator

        #if targetEnvironment(simulator)
        // Simulator input is a mouse or touch, so it cannot synthesize Pencil ink.
        canvas.drawingPolicy = .anyInput
        #else
        canvas.drawingPolicy = .pencilOnly
        #endif

        // Tool picker
        let toolPicker = PKToolPicker()
        CanvasAppearance.apply(colorScheme, to: canvas, toolPicker: toolPicker)
        context.coordinator.isDrawingActive = isDrawingActive && !isSelectingExportBounds
        toolPicker.setVisible(context.coordinator.isDrawingActive, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        context.coordinator.toolPicker = toolPicker

        Task { @MainActor in
            if context.coordinator.isDrawingActive { canvas.becomeFirstResponder() }
        }

        return surface
    }

    func updateUIView(_ surface: CanvasDocumentSurface, context: Context) {
        InteractionDiagnostics.shared.record(.canvasUpdate)
        let canvas = surface.canvas
        canvas.viewModel = viewModel
        context.coordinator.viewModel = viewModel
        surface.apply(viewModel, selecting: isSelectingExportBounds, onSelection: onExportBoundsSelected)
        CanvasAppearance.apply(colorScheme, to: canvas, toolPicker: context.coordinator.toolPicker)
        let drawingActive = isDrawingActive && !isSelectingExportBounds
        if context.coordinator.isDrawingActive != drawingActive {
            context.coordinator.isDrawingActive = drawingActive
            context.coordinator.toolPicker?.setVisible(drawingActive, forFirstResponder: canvas)
            if drawingActive { canvas.becomeFirstResponder() }
            else if canvas.isFirstResponder { canvas.resignFirstResponder() }
        }
    }

    static func dismantleUIView(_ surface: CanvasDocumentSurface, coordinator: Coordinator) {
        let canvas = surface.canvas
        coordinator.toolPicker?.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker?.removeObserver(canvas)
        canvas.resignFirstResponder()
        coordinator.toolPicker = nil
        canvas.delegate = nil
        surface.saveViewport()
        coordinator.viewModel.save()
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var viewModel: CanvasViewModel
        var toolPicker: PKToolPicker?
        weak var surface: CanvasDocumentSurface?
        var isDrawingActive = true
        private var gestureID: UUID?
        private var isUsingTool = false

        init(viewModel: CanvasViewModel) {
            self.viewModel = viewModel
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            InteractionDiagnostics.shared.record(.canvasDrawingCallback)
            // PencilKit renders live ink itself. Translate back to document
            // coordinates at tool-up, not on every wet-ink callback.
            guard !isUsingTool else { return }
            commitDrawing(canvasView)
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            gestureID = UUID()
            isUsingTool = true
            surface?.isUsingTool = true
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            isUsingTool = false
            surface?.isUsingTool = false
            commitDrawing(canvasView)
            viewModel.save()
            surface?.viewportDidChange()
            surface?.setNeedsLayout()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            surface?.viewportDidChange()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            InteractionDiagnostics.shared.record(.canvasZoom)
            surface?.layoutDocumentLayers()
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate { surface?.finishNavigation() }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            surface?.finishNavigation()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            surface?.finishNavigation()
        }

        private func commitDrawing(_ canvasView: PKCanvasView) {
            guard let surface, !surface.isUpdatingCanvas else { return }
            InteractionDiagnostics.shared.record(.canvasDrawingCommit)
            let drawing = surface.documentDrawing(from: canvasView.drawing)
            surface.acceptDrawing(drawing)
            viewModel.updateDrawing(drawing, gestureID: gestureID)
        }
    }
}

final class CanvasDocumentSurface: UIView {
    let canvas = CanvasDrawingView()
    private let referenceView = UIImageView()
    private let selectionLayer = CAShapeLayer()
    private lazy var selectionGesture = UIPanGestureRecognizer(target: self, action: #selector(selectExportArea))
    private weak var viewModel: CanvasViewModel?
    private var referenceID: UUID?
    private var referenceBounds: CGRect?
    private var contentBounds = CanvasDocument.emptyBounds
    private var selectedBounds: CGRect?
    private var selectionStart: CGPoint?
    private var selectionPreview: CGRect?
    private var onSelection: (() -> Void)?
    private var scrollWindow: CanvasScrollWindow?
    private var viewportSize = CGSize.zero
    private var displayedDrawing: PKDrawing?
    private var handledViewportCommandID = 0
    private(set) var isUpdatingCanvas = false
    var isUsingTool = false
    private var atCoordinateLimit = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isOpaque = true
        referenceView.isUserInteractionEnabled = false
        addSubview(referenceView)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.minimumZoomScale = CanvasViewport.minimumZoom
        canvas.maximumZoomScale = CanvasViewport.maximumZoom
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.showsHorizontalScrollIndicator = false
        canvas.showsVerticalScrollIndicator = false
        canvas.bouncesZoom = false
        canvas.isAccessibilityElement = true
        canvas.accessibilityLabel = "Drawing canvas"
        canvas.accessibilityHint = "Draw with Apple Pencil. Pan with a finger and pinch to zoom. Canvas editing includes zoom and fit controls."
        canvas.accessibilityIdentifier = "canvas.drawing"
        addSubview(canvas)
        selectionLayer.fillColor = UIColor.clear.cgColor
        selectionLayer.strokeColor = UIColor.systemOrange.cgColor
        selectionLayer.lineWidth = 2
        selectionLayer.lineDashPattern = [6, 4]
        layer.addSublayer(selectionLayer)
        selectionGesture.maximumNumberOfTouches = 1
        selectionGesture.isEnabled = false
        addGestureRecognizer(selectionGesture)
    }

    required init?(coder: NSCoder) { return nil }

    func apply(_ model: CanvasViewModel, selecting: Bool, onSelection: (() -> Void)?) {
        InteractionDiagnostics.shared.record(.canvasApply)
        viewModel = model
        backgroundColor = model.background.uiColor
        contentBounds = model.contentBounds
        selectedBounds = model.selectedExportBounds
        self.onSelection = onSelection
        if referenceID != model.referenceImage?.id {
            referenceID = model.referenceImage?.id
            referenceView.image = model.referenceImage.flatMap { UIImage(data: $0.data) }
        }
        referenceBounds = model.referenceImage?.bounds
        referenceView.isHidden = referenceBounds == nil
        selectionGesture.isEnabled = selecting
        canvas.drawingGestureRecognizer.isEnabled = !selecting
        canvas.isScrollEnabled = !selecting
        if !selecting {
            selectionStart = nil
            selectionPreview = nil
        }
        if scrollWindow != nil, displayedDrawing != model.drawing, !isUsingTool {
            replaceDisplayedDrawing(model.drawing)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        InteractionDiagnostics.shared.canvas(.canvasLayout, bounds: bounds, offset: canvas.contentOffset, zoom: canvas.zoomScale)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let previous = currentViewport
        isUpdatingCanvas = true
        canvas.frame = bounds
        isUpdatingCanvas = false
        if scrollWindow == nil {
            InteractionDiagnostics.shared.record(.canvasPositionInitial)
            let initial = viewModel?.viewport
                ?? CanvasViewport(center: CGPoint(x: contentBounds.midX, y: contentBounds.midY), zoom: 1)
            positionViewport(initial, rebuildWindow: true)
        } else if viewportSize != bounds.size {
            InteractionDiagnostics.shared.record(.canvasPositionResize)
            // Preserve the document point at the center while rotating or
            // resizing the chat pane. Do not transform ink on every layout.
            positionViewport(previous, rebuildWindow: scrollWindow?.canContain(bounds.size) != true)
        }
        viewportSize = bounds.size
        applyViewportCommand()
        layoutDocumentLayers()
    }

    var currentViewport: CanvasViewport {
        guard let scrollWindow else {
            return viewModel?.viewport ?? CanvasViewport(center: .zero, zoom: 1)
        }
        let size = viewportSize == .zero ? bounds.size : viewportSize
        return CanvasViewport(center: scrollWindow.documentPoint(
            at: CGPoint(x: size.width / 2, y: size.height / 2),
            contentOffset: canvas.contentOffset, zoom: canvas.zoomScale), zoom: canvas.zoomScale)
    }

    func documentPoint(at point: CGPoint) -> CGPoint {
        scrollWindow?.documentPoint(at: point, contentOffset: canvas.contentOffset, zoom: canvas.zoomScale) ?? point
    }

    func documentDrawing(from drawing: PKDrawing) -> PKDrawing {
        guard let scrollWindow else { return drawing }
        return drawing.transformed(using: CGAffineTransform(translationX: scrollWindow.origin.x, y: scrollWindow.origin.y))
    }

    func acceptDrawing(_ drawing: PKDrawing) {
        displayedDrawing = drawing
    }

    func viewportDidChange() {
        InteractionDiagnostics.shared.record(.canvasScroll)
        guard !isUpdatingCanvas, let scrollWindow else { return }
        if !isUsingTool, !canvas.isZooming, viewportSize == bounds.size {
            let viewport = currentViewport
            let constrained = viewport.constrained(to: bounds.size)
            atCoordinateLimit = constrained.isAtCoordinateLimit(in: bounds.size)
            if constrained != viewport || scrollWindow.needsRecentering(
                contentOffset: canvas.contentOffset, viewportSize: bounds.size, zoom: canvas.zoomScale
            ) {
                InteractionDiagnostics.shared.record(.canvasPositionRecenter)
                positionViewport(constrained, rebuildWindow: true)
            }
        }
        layoutDocumentLayers()
    }

    func finishNavigation() {
        viewportDidChange()
        saveViewport()
    }

    func saveViewport() {
        guard scrollWindow != nil, bounds.width > 0, bounds.height > 0 else { return }
        InteractionDiagnostics.shared.record(.canvasViewportSave)
        viewModel?.saveViewport(currentViewport.constrained(to: bounds.size), atCoordinateLimit: atCoordinateLimit)
    }

    func layoutDocumentLayers() {
        guard let scrollWindow else { return }
        InteractionDiagnostics.shared.canvas(.canvasLayers, bounds: bounds, offset: canvas.contentOffset, zoom: canvas.zoomScale)
        let offset = canvas.contentOffset
        let zoom = canvas.zoomScale
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let referenceBounds {
            referenceView.frame = scrollWindow.surfaceRect(for: referenceBounds, contentOffset: offset, zoom: zoom)
        }
        selectionLayer.frame = bounds
        let selection = selectionPreview ?? selectedBounds
        selectionLayer.path = selection.map {
            UIBezierPath(rect: scrollWindow.surfaceRect(for: $0, contentOffset: offset, zoom: zoom)).cgPath
        }
        CATransaction.commit()
        let viewport = currentViewport
        let description = String(format: "Zoom %.0f%%. Center %.1f, %.1f.",
                                 viewport.zoom * 100, viewport.center.x, viewport.center.y)
        if canvas.accessibilityValue != description { canvas.accessibilityValue = description }
    }

    private func positionViewport(_ requested: CanvasViewport, rebuildWindow: Bool) {
        guard let viewModel else { return }
        InteractionDiagnostics.shared.record(.canvasPosition)
        let viewport = requested.constrained(to: bounds.size)
        isUpdatingCanvas = true
        if rebuildWindow || scrollWindow == nil {
            InteractionDiagnostics.shared.record(.canvasWindowRebuild)
            scrollWindow = CanvasScrollWindow(center: viewport.center, viewportSize: bounds.size)
        }
        guard let scrollWindow else { isUpdatingCanvas = false; return }
        if canvas.zoomScale != viewport.zoom { canvas.setZoomScale(viewport.zoom, animated: false) }
        canvas.contentSize = CGSize(width: scrollWindow.size.width * viewport.zoom,
                                    height: scrollWindow.size.height * viewport.zoom)
        if rebuildWindow { setCanvasDrawing(viewModel.drawing) }
        canvas.setContentOffset(scrollWindow.contentOffset(for: viewport, viewportSize: bounds.size), animated: false)
        isUpdatingCanvas = false
    }

    private func replaceDisplayedDrawing(_ drawing: PKDrawing) {
        isUpdatingCanvas = true
        setCanvasDrawing(drawing)
        isUpdatingCanvas = false
    }

    private func setCanvasDrawing(_ drawing: PKDrawing) {
        guard let scrollWindow else { return }
        displayedDrawing = drawing
        canvas.drawing = drawing.transformed(using: CGAffineTransform(
            translationX: -scrollWindow.origin.x, y: -scrollWindow.origin.y))
    }

    private func applyViewportCommand() {
        guard let viewModel, handledViewportCommandID != viewModel.viewportCommandID,
              let command = viewModel.viewportCommand, !isUsingTool else { return }
        handledViewportCommandID = viewModel.viewportCommandID
        InteractionDiagnostics.shared.record(.canvasPositionCommand)
        var viewport = currentViewport
        switch command {
        case .fitContent: viewport = .fitting(contentBounds, in: bounds.size)
        case .actualSize: viewport.zoom = 1
        case .zoomIn: viewport.zoom *= 1.5
        case .zoomOut: viewport.zoom /= 1.5
        }
        atCoordinateLimit = false
        positionViewport(viewport, rebuildWindow: true)
        viewModel.completeCanvasNavigation(handledViewportCommandID)
        saveViewport()
    }

    @objc private func selectExportArea(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        let point = documentPoint(at: location)
        switch gesture.state {
        case .began:
            let translation = gesture.translation(in: self)
            selectionStart = CGPoint(x: point.x - translation.x / canvas.zoomScale,
                                     y: point.y - translation.y / canvas.zoomScale)
        case .changed, .ended:
            guard let start = selectionStart else { return }
            let rectangle = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                                   width: abs(point.x - start.x), height: abs(point.y - start.y))
            selectionPreview = rectangle
            if gesture.state == .ended {
                if rectangle.width >= 8, rectangle.height >= 8,
                   (try? viewModel?.setExportBounds(rectangle)) != nil {
                    selectedBounds = rectangle
                    onSelection?()
                }
                selectionStart = nil
                selectionPreview = nil
            }
        case .cancelled, .failed:
            selectionStart = nil
            selectionPreview = nil
        default:
            break
        }
        layoutDocumentLayers()
    }
}

final class CanvasDrawingView: PKCanvasView {
    weak var viewModel: CanvasViewModel?

    // Undo belongs to the document. A recreated UIKit view must not replay
    // native undo actions that retain a previous canvas instance.
    override var undoManager: UndoManager? { nil }

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "z", modifierFlags: .command, action: #selector(undoDocument)),
            UIKeyCommand(input: "z", modifierFlags: [.command, .shift], action: #selector(redoDocument))
        ]
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(undoDocument) { return viewModel?.canUndo == true }
        if action == #selector(redoDocument) { return viewModel?.canRedo == true }
        return super.canPerformAction(action, withSender: sender)
    }

    @objc private func undoDocument() { viewModel?.undo() }
    @objc private func redoDocument() { viewModel?.redo() }
}
