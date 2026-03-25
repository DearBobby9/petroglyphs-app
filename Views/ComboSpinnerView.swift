import SwiftUI

struct ComboSpinnerView: View {
    @Environment(ComboStore.self) var comboStore
    @Binding var editingCombo: Combo?
    let onCast: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                ForEach(comboStore.combos) { combo in
                    let isActive = combo.id == comboStore.activeComboId

                    ComboCell(
                        combo: combo,
                        isActive: isActive,
                        onTap: {
                            if isActive {
                                onCast()
                            } else {
                                comboStore.setActive(combo)
                            }
                        },
                        onLongPress: {
                            editingCombo = combo
                        }
                    )
                }

                // Add new combo
                Button {
                    editingCombo = Combo(id: UUID().uuidString, name: "", icon: "✏️", prompt: "", auto_action: nil, color: "#D4874D")
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color.ochre)
                        .frame(width: 68, height: 44)
                        .background(Color.sandstone.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
        }
        .background(Color.limestone.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}
