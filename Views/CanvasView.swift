import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var onFirstStroke: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing, onFirstStroke: onFirstStroke)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.backgroundColor = .white
        canvas.isOpaque = true
        canvas.delegate = context.coordinator

        #if targetEnvironment(simulator)
        canvas.drawingPolicy = .anyInput
        #else
        canvas.drawingPolicy = .pencilOnly
        #endif

        // Tool picker
        let toolPicker = PKToolPicker()
        toolPicker.setVisible(true, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        context.coordinator.toolPicker = toolPicker

        DispatchQueue.main.async {
            canvas.becomeFirstResponder()
        }

        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawing: PKDrawing
        var onFirstStroke: () -> Void
        var toolPicker: PKToolPicker?
        private var hasStrokedOnce = false

        init(drawing: Binding<PKDrawing>, onFirstStroke: @escaping () -> Void) {
            _drawing = drawing
            self.onFirstStroke = onFirstStroke
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing = canvasView.drawing
            if !hasStrokedOnce && !canvasView.drawing.strokes.isEmpty {
                hasStrokedOnce = true
                onFirstStroke()
            }
        }
    }
}
