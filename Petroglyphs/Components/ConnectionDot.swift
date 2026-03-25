import SwiftUI

struct ConnectionDot: View {
    let isConnected: Bool

    var body: some View {
        Circle()
            .fill(isConnected ? Color.moss : Color.rust)
            .frame(width: 10, height: 10)
            .shadow(color: isConnected ? Color.moss.opacity(0.5) : .clear, radius: 4)
    }
}
