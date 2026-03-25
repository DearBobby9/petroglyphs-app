import SwiftUI

struct ComboEditorPopover: View {
    @Environment(ComboStore.self) var comboStore
    @Binding var combo: Combo?
    @State private var vm = ComboEditorViewModel()

    let autoActionOptions = ["", "save_to_obsidian", "export_to_excalidraw"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    HStack {
                        TextField("Icon (emoji)", text: $vm.icon)
                            .frame(width: 60)
                        TextField("Name", text: $vm.name)
                    }
                }
                Section("Prompt") {
                    TextEditor(text: $vm.prompt)
                        .frame(minHeight: 80)
                }
                Section("Auto-action") {
                    Picker("Tool", selection: $vm.autoAction) {
                        Text("None").tag("")
                        Text("Save to Obsidian").tag("save_to_obsidian")
                        Text("Export to Excalidraw").tag("export_to_excalidraw")
                    }
                }
                Section("Color") {
                    TextField("Hex color", text: $vm.color)
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: vm.color))
                        .frame(height: 32)
                }
            }
            .navigationTitle(vm.name.isEmpty ? "New Combo" : vm.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { combo = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let c = combo, vm.isValid else { return }
                        let updated = vm.build(id: c.id)
                        if comboStore.combos.contains(where: { $0.id == c.id }) {
                            comboStore.update(updated)
                        } else {
                            comboStore.add(updated)
                        }
                        combo = nil
                    }
                    .disabled(!vm.isValid)
                }
            }
        }
        .onAppear {
            if let c = combo {
                vm.load(from: c)
            }
        }
        .presentationDetents([.medium, .large])
    }
}
