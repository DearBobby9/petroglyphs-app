import SwiftUI

struct CastSuccessOverlay: View {
    @Binding var isShowing: Bool

    @State private var ring1Scale: CGFloat = 0.3
    @State private var ring1Opacity: Double = 0
    @State private var ring2Scale: CGFloat = 0.3
    @State private var ring2Opacity: Double = 0
    @State private var iconScale: CGFloat = 0.0
    @State private var iconOpacity: Double = 0

    var body: some View {
        if isShowing {
            ZStack {
                // Outer ripple ring
                Circle()
                    .stroke(Color.ochre.opacity(0.4), lineWidth: 2)
                    .frame(width: 80, height: 80)
                    .scaleEffect(ring2Scale)
                    .opacity(ring2Opacity)

                // Inner ripple ring
                Circle()
                    .stroke(Color.ochre, lineWidth: 2.5)
                    .frame(width: 60, height: 60)
                    .scaleEffect(ring1Scale)
                    .opacity(ring1Opacity)

                // Checkmark icon
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.ochre)
                    .scaleEffect(iconScale)
                    .opacity(iconOpacity)
            }
            .onAppear {
                // Inner ring expands first
                withAnimation(.easeOut(duration: 0.4)) {
                    ring1Scale = 2.0
                    ring1Opacity = 0.7
                }

                // Outer ring follows with slight delay
                withAnimation(.easeOut(duration: 0.5).delay(0.08)) {
                    ring2Scale = 3.0
                    ring2Opacity = 0.5
                }

                // Checkmark pops in with spring
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6).delay(0.1)) {
                    iconScale = 1.0
                    iconOpacity = 1.0
                }

                // Fade everything out
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    withAnimation(.easeIn(duration: 0.25)) {
                        ring1Opacity = 0
                        ring2Opacity = 0
                        iconOpacity = 0
                    }
                }

                // Reset
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                    isShowing = false
                    ring1Scale = 0.3
                    ring2Scale = 0.3
                    iconScale = 0.0
                }
            }
            .allowsHitTesting(false)
        }
    }
}
