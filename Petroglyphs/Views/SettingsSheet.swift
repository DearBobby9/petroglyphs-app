import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("darkModeEnabled") private var darkModeEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Toggle("Dark mode", isOn: $darkModeEnabled)
                        .accessibilityIdentifier("settings.darkMode")
                }
                Section("About") {
                    LabeledContent("Version", value: "0.1.0")
                    LabeledContent("License", value: "MIT")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(darkModeEnabled ? .dark : .light)
    }
}
