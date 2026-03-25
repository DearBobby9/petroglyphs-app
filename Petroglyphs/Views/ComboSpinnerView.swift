import SwiftUI

struct ComboSpinnerView: View {
    @Environment(ComboStore.self) var comboStore
    @Binding var editingCombo: Combo?
    @Binding var isExpanded: Bool
    let isRightSide: Bool
    let onCast: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Chevron handle (left side when right-aligned)
            if isRightSide {
                chevronHandle
            }

            if isExpanded {
                expandedList
                    .transition(.move(edge: isRightSide ? .trailing : .leading).combined(with: .opacity))
            }

            // Chevron handle (right side when left-aligned)
            if !isRightSide {
                chevronHandle
            }
        }
        .animation(.spring(duration: 0.3), value: isExpanded)
    }

    // MARK: - Collapsed: active combo pill + expand handle

    private var chevronHandle: some View {
        VStack(spacing: 8) {
            // Active combo as the cast button
            if let active = comboStore.activeCombo {
                Button {
                    onCast()
                } label: {
                    VStack(spacing: 4) {
                        Text(active.icon)
                            .font(.title)
                        Text(active.name)
                            .font(.rounded(9, weight: .semibold))
                            .foregroundStyle(Color.charcoal)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(hex: active.color).opacity(0.2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color(hex: active.color), lineWidth: 2)
                            )
                    )
                }
                .buttonStyle(.plain)
            }

            // Expand/collapse chevron
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded
                      ? (isRightSide ? "chevron.right" : "chevron.left")
                      : (isRightSide ? "chevron.left" : "chevron.right"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.charcoal.opacity(0.4))
                    .padding(12)
                    .background(Color.sandstone.opacity(0.5))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: 76)
    }

    // MARK: - Expanded: scrollable combo list

    private var expandedList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                ForEach(comboStore.combos) { combo in
                    let isActive = combo.id == comboStore.activeComboId

                    Button {
                        if isActive {
                            onCast()
                        } else {
                            comboStore.setActive(combo)
                        }
                        withAnimation { isExpanded = false }
                    } label: {
                        HStack(spacing: 8) {
                            Text(combo.icon).font(.title3)
                            Text(combo.name)
                                .font(.rounded(13, weight: isActive ? .semibold : .regular))
                                .foregroundStyle(Color.charcoal)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isActive ? Color(hex: combo.color).opacity(0.15) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                            editingCombo = combo
                        }
                    )
                }

                // Add button
                Button {
                    editingCombo = Combo(id: UUID().uuidString, name: "", icon: "\u{270F}\u{FE0F}", prompt: "", auto_action: nil, color: "#D4874D")
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.ochre)
                        Text("New combo")
                            .font(.rounded(13))
                            .foregroundStyle(Color.charcoal.opacity(0.6))
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                }
                .buttonStyle(.plain)
            }
            .padding(8)
        }
        .frame(width: 200)
        .background(Color.sandstone.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.08), radius: 8, x: isRightSide ? -2 : 2, y: 2)
    }
}
