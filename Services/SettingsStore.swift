import SwiftUI

enum Handedness: String {
    case right, left
}

class SettingsStore: ObservableObject {
    @AppStorage("serverURLString") var serverURLString: String = ""
    @AppStorage("handedness") private var handednessRaw: String = Handedness.right.rawValue

    var serverURL: URL? {
        guard !serverURLString.isEmpty else { return nil }
        let raw = serverURLString.hasPrefix("http") ? serverURLString : "http://\(serverURLString)"
        return URL(string: raw)
    }

    var handedness: Handedness {
        get { Handedness(rawValue: handednessRaw) ?? .right }
        set { handednessRaw = newValue.rawValue }
    }
}
