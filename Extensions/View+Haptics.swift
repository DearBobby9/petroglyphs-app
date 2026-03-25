import SwiftUI

extension View {
    func castHaptic() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func clearHaptic() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }
}

func triggerCastHaptic() {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
}

func triggerClearHaptic() {
    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
}
