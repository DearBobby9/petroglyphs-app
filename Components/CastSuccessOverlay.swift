import SwiftUI

struct CastSuccessOverlay: View {
    @Binding var isShowing: Bool
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0

    var body: some View {
        if isShowing {
            Circle()
                .stroke(Color.ochre, lineWidth: 3)
                .frame(width: 80, height: 80)
                .scaleEffect(scale)
                .opacity(opacity)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.5)) {
                        scale = 2.5
                        opacity = 0.8
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        withAnimation(.easeIn(duration: 0.2)) {
                            opacity = 0
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                        isShowing = false
                        scale = 0.5
                    }
                }
                .allowsHitTesting(false)
        }
    }
}
