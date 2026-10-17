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
        let surface = CanvasDocumentSurface()
        let canvas = surface.canvas
        surface.apply(viewModel, selecting: isSelectingExportBounds, onSelection: onExportBoundsSelected)
        context.coordinator.surface = surface
        canvas.viewModel = viewModel
        canvas.drawing = viewModel.drawing
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
        if canvas.drawing != viewModel.drawing {
            context.coordinator.isApplyingModel = true
            canvas.drawing = viewModel.drawing
            context.coordinator.isApplyingModel = false
        }
    }

    static func dismantleUIView(_ surface: CanvasDocumentSurface, coordinator: Coordinator) {
        let canvas = surface.canvas
        coordinator.toolPicker?.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker?.removeObserver(canvas)
        canvas.resignFirstResponder()
        coordinator.toolPicker = nil
        canvas.delegate = nil
        coordinator.viewModel.save()
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var viewModel: CanvasViewModel
        var toolPicker: PKToolPicker?
        weak var surface: CanvasDocumentSurface?
        var isDrawingActive = true
        var isApplyingModel = false
        private var gestureID: UUID?
        private var isUsingTool = false

        init(viewModel: CanvasViewModel) {
            self.viewModel = viewModel
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !isApplyingModel else { return }
            viewModel.updateDrawing(canvasView.drawing, gestureID: gestureID, saveImmediately: !isUsingTool)
        }

        func canvasViewDidBeginUsingTool(_ canvasView: PKCanvasView) {
            gestureID = UUID()
            isUsingTool = true
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            isUsingTool = false
            viewModel.updateDrawing(canvasView.drawing, gestureID: gestureID)
            viewModel.save()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            surface?.layoutDocumentLayers()
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

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        isOpaque = true
        referenceView.isUserInteractionEnabled = false
        addSubview(referenceView)
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        // The image and ink use the same document coordinates. Fingers scroll;
        // image inspection supports zoom in the separate preview.
        canvas.minimumZoomScale = 1
        canvas.maximumZoomScale = 1
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
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
        let size = CGSize(width: max(bounds.width, contentBounds.maxX + 24),
                          height: max(bounds.height, contentBounds.maxY + 24))
        if canvas.contentSize != size { canvas.contentSize = size }
        layoutDocumentLayers()
    }

    func layoutDocumentLayers() {
        let offset = canvas.contentOffset
        if let referenceBounds {
            referenceView.frame = referenceBounds.offsetBy(dx: -offset.x, dy: -offset.y)
        }
        selectionLayer.frame = bounds
        let selection = selectionPreview ?? selectedBounds
        selectionLayer.path = selection.map {
            UIBezierPath(rect: $0.offsetBy(dx: -offset.x, dy: -offset.y)).cgPath
        }
    }

    @objc private func selectExportArea(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: self)
        let point = CGPoint(x: location.x + canvas.contentOffset.x, y: location.y + canvas.contentOffset.y)
        switch gesture.state {
        case .began:
            let translation = gesture.translation(in: self)
            selectionStart = CGPoint(x: point.x - translation.x, y: point.y - translation.y)
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
