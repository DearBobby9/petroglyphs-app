import SwiftUI

struct ComboManagerSheet: View {
    @Environment(ComboStore.self) var comboStore
    @State private var editingCombo: Combo?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(comboStore.combos) { combo in
                    HStack(spacing: 12) {
                        Text(combo.icon).font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(combo.name).font(.rounded(16, weight: .medium))
                            if !combo.prompt.isEmpty {
                                Text(combo.prompt)
                                    .font(.rounded(12))
                                    .foregroundStyle(Color.charcoal.opacity(0.5))
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Circle()
                            .fill(Color(hex: combo.color))
                            .frame(width: 14, height: 14)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { editingCombo = combo }
                }
                .onDelete { comboStore.combos.remove(atOffsets: $0); comboStore.move(from: IndexSet(), to: 0) }
                .onMove { comboStore.move(from: $0, to: $1) }
            }
            .navigationTitle("Combos")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    EditButton()
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingCombo = Combo(id: UUID().uuidString, name: "", icon: "✏️", prompt: "", auto_action: nil, color: "#D4874D")
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(item: $editingCombo) { combo in
            ComboEditorPopover(combo: Binding(
                get: { editingCombo },
                set: { editingCombo = $0 }
            ))
        }
    }
}
