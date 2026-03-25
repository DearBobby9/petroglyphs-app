import Foundation

struct Combo: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var icon: String
    var prompt: String
    var auto_action: String?
    var color: String
}
