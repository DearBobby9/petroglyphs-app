import SwiftUI

@Observable
class ComboEditorViewModel {
    var name: String = ""
    var icon: String = "✏️"
    var prompt: String = ""
    var autoAction: String = ""
    var color: String = "#D4874D"

    var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    func load(from combo: Combo) {
        name = combo.name
        icon = combo.icon
        prompt = combo.prompt
        autoAction = combo.auto_action ?? ""
        color = combo.color
    }

    func build(id: String) -> Combo {
        Combo(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            icon: icon,
            prompt: prompt,
            auto_action: autoAction.isEmpty ? nil : autoAction,
            color: color
        )
    }
}
