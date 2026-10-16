import SwiftUI
import PencilKit

enum CanvasAppearance {
    @MainActor
    static func apply(_ colorScheme: ColorScheme, to canvas: PKCanvasView, toolPicker: PKToolPicker?) {
        // The paper and stored ink are literal colors. Only the picker chrome follows the interface.
        canvas.overrideUserInterfaceStyle = .light
        toolPicker?.colorUserInterfaceStyle = .light
        toolPicker?.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
    }
}
