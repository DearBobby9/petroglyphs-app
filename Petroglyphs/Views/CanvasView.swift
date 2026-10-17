import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var viewModel: CanvasViewModel
    var isDrawingActive = true

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> CanvasDrawingView {
        let canvas = CanvasDrawingView()
        canvas.viewModel = viewModel
        canvas.drawing = viewModel.drawing
        canvas.backgroundColor = viewModel.background.uiColor
        canvas.isOpaque = true
        canvas.delegate = context.coordinator

        canvas.drawingPolicy = .pencilOnly

        // Tool picker
        let toolPicker = PKToolPicker()
        CanvasAppearance.apply(colorScheme, to: canvas, toolPicker: toolPicker)
        context.coordinator.isDrawingActive = isDrawingActive
        toolPicker.setVisible(isDrawingActive, forFirstResponder: canvas)
        toolPicker.addObserver(canvas)
        context.coordinator.toolPicker = toolPicker

        Task { @MainActor in
            if context.coordinator.isDrawingActive { canvas.becomeFirstResponder() }
        }

        return canvas
    }

    func updateUIView(_ canvas: CanvasDrawingView, context: Context) {
        canvas.viewModel = viewModel
        context.coordinator.viewModel = viewModel
        CanvasAppearance.apply(colorScheme, to: canvas, toolPicker: context.coordinator.toolPicker)
        if context.coordinator.isDrawingActive != isDrawingActive {
            context.coordinator.isDrawingActive = isDrawingActive
            context.coordinator.toolPicker?.setVisible(isDrawingActive, forFirstResponder: canvas)
            if isDrawingActive { canvas.becomeFirstResponder() }
            else if canvas.isFirstResponder { canvas.resignFirstResponder() }
        }
        canvas.backgroundColor = viewModel.background.uiColor
        if canvas.drawing != viewModel.drawing {
            context.coordinator.isApplyingModel = true
            canvas.drawing = viewModel.drawing
            context.coordinator.isApplyingModel = false
        }
    }

    static func dismantleUIView(_ canvas: CanvasDrawingView, coordinator: Coordinator) {
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
