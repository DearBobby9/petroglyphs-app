import SwiftUI

struct SettingTile: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(Color.burntOchre)
                Text(label)
                    .font(.rounded(14, weight: .medium))
                    .foregroundStyle(Color.charcoal)
            }
            .frame(width: 110, height: 90)
            .sandstoneCard()
        }
        .buttonStyle(.plain)
    }
}
