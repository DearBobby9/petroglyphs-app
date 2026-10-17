import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var viewModel: CanvasViewModel
    var isDrawingActive = true

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = viewModel.drawing
        canvas.backgroundColor = viewModel.background.uiColor
        canvas.isOpaque = true
        canvas.delegate = context.coordinator

        canvas.drawingPolicy = .pencilOnly

        // Palm/finger swipe to clear (works because pencilOnly ignores non-pencil for drawing)
        let palmSwipe = PalmSwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClear))
        canvas.addGestureRecognizer(palmSwipe)

        // Three-finger swipe to clear (fallback)
        let threeFingerSwipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClear))
        threeFingerSwipe.numberOfTouchesRequired = 3
        threeFingerSwipe.direction = .left
        canvas.addGestureRecognizer(threeFingerSwipe)

        // Tool picker
        let toolPicker = PKToolPicker()
        CanvasAppearance.apply(colorScheme, to: canvas, toolPicker: toolPicker)
        context.coordinator.isDrawingActive = isDrawingActive
        toolPicker.setVisible(isDrawingActive, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        context.coordinator.toolPicker = toolPicker

        DispatchQueue.main.async {
            if context.coordinator.isDrawingActive { canvas.becomeFirstResponder() }
        }

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        CanvasAppearance.apply(colorScheme, to: canvas, toolPicker: context.coordinator.toolPicker)
        if context.coordinator.isDrawingActive != isDrawingActive {
            context.coordinator.isDrawingActive = isDrawingActive
            context.coordinator.toolPicker?.setVisible(isDrawingActive, forFirstResponder: canvas)
            if isDrawingActive { canvas.becomeFirstResponder() }
            else if canvas.isFirstResponder { canvas.resignFirstResponder() }
        }
        canvas.backgroundColor = viewModel.background.uiColor
        if canvas.drawing != viewModel.drawing {
            canvas.drawing = viewModel.drawing
        }
    }

    static func dismantleUIView(_ canvas: PKCanvasView, coordinator: Coordinator) {
        coordinator.toolPicker?.setVisible(false, forFirstResponder: canvas)
        coordinator.toolPicker?.removeObserver(canvas)
        canvas.resignFirstResponder()
        coordinator.toolPicker = nil
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        let viewModel: CanvasViewModel
        var toolPicker: PKToolPicker?
        var isDrawingActive = true
        private var hasStrokedOnce = false

        init(viewModel: CanvasViewModel) {
            self.viewModel = viewModel
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            viewModel.drawing = canvasView.drawing
            if !hasStrokedOnce && !canvasView.drawing.strokes.isEmpty {
                hasStrokedOnce = true
                viewModel.onFirstStroke()
            }
        }

        @objc func handleClear() { viewModel.clear() }
    }
}

// MARK: - Palm/finger swipe gesture recognizer

/// Detects a horizontal finger or palm swipe across >50% of the canvas width.
/// Works with pencilOnly drawing policy — non-pencil touches don't draw but still fire gestures.
class PalmSwipeGestureRecognizer: UIGestureRecognizer {
    private var startX: CGFloat = 0
    private var startTime: TimeInterval = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        // Only respond to finger/palm touches, not pencil
        if touch.type == .pencil {
            state = .failed
            return
        }
        startX = touch.location(in: view).x
        startTime = touch.timestamp
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, let view = view else { return }
        let currentX = touch.location(in: view).x
        let distance = abs(currentX - startX)
        let elapsed = touch.timestamp - startTime

        // Swipe must cover >50% of canvas width within 1 second
        if distance > view.bounds.width * 0.5 && elapsed < 1.0 {
            state = .recognized
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if state != .recognized { state = .failed }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }

    override func reset() {
        startX = 0
        startTime = 0
    }
}
