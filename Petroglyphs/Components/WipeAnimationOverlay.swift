import SwiftUI

struct WipeAnimationOverlay: View {
    @Binding var isShowing: Bool
    @State private var offset: CGFloat = 0
    @State private var started = false

    var body: some View {
        if isShowing {
            GeometryReader { geo in
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.limestone.opacity(0), Color.limestone.opacity(0.85), Color.limestone.opacity(0)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: 120)
                    .offset(x: started ? geo.size.width + 60 : -120)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 0.45)) {
                            started = true
                        }
                    }
            }
            .allowsHitTesting(false)
        }
    }
}
