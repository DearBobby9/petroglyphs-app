import Foundation

@Observable
class ComboStore {
    var combos: [Combo] = []
    var activeComboId: String = "just-cast"

    private let key = "savedCombos"

    init() {
        load()
    }

    var activeCombo: Combo? {
        combos.first { $0.id == activeComboId }
    }

    func setActive(_ combo: Combo) {
        activeComboId = combo.id
    }

    func add(_ combo: Combo) {
        combos.append(combo)
        save()
    }

    func update(_ combo: Combo) {
        guard let idx = combos.firstIndex(where: { $0.id == combo.id }) else { return }
        combos[idx] = combo
        save()
    }

    func delete(_ combo: Combo) {
        combos.removeAll { $0.id == combo.id }
        if activeComboId == combo.id { activeComboId = combos.first?.id ?? "" }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        combos.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([Combo].self, from: data) {
            combos = saved
        } else {
            combos = loadDefaults()
            save()
        }
        if activeComboId.isEmpty { activeComboId = combos.first?.id ?? "" }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(combos) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func loadDefaults() -> [Combo] {
        guard let url = Bundle.main.url(forResource: "DefaultCombos", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let combos = try? JSONDecoder().decode([Combo].self, from: data)
        else { return [] }
        return combos
    }
}
