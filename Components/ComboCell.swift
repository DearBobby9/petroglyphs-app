import SwiftUI

struct ComboCell: View {
    let combo: Combo
    let isActive: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Text(combo.icon)
                    .font(.system(size: isActive ? 30 : 22))
                Text(combo.name)
                    .font(.rounded(isActive ? 13 : 11, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(Color.charcoal)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, isActive ? 14 : 10)
            .padding(.horizontal, 8)
            .frame(width: isActive ? 80 : 68)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isActive ? Color(hex: combo.color).opacity(0.15) : Color.sandstone.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isActive ? Color(hex: combo.color) : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in onLongPress() }
        )
        .animation(.spring(duration: 0.2), value: isActive)
    }
}
