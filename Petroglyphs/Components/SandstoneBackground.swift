import SwiftUI

struct SandstoneBackground: View {
    var body: some View {
        ZStack {
            Color.limestone.ignoresSafeArea()
            // Grain texture overlay — add sandstone-grain.png to Assets.xcassets
            // and uncomment when the asset is available:
            // Image("sandstone-grain")
            //     .resizable()
            //     .ignoresSafeArea()
            //     .opacity(0.10)
        }
    }
}
