import SwiftUI

struct ServerSettingsSheet: View {
    @Environment(ConnectionMonitor.self) var connectionMonitor
    @Environment(\.dismiss) var dismiss
    @AppStorage("serverURLString") private var serverURLString: String = ""
    @State private var input: String = ""
    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("MCP Server") {
                    TextField("192.168.x.x:3333 or localhost:3333", text: $input)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section {
                    Button {
                        testConnection()
                    } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            if isTesting {
                                ProgressView()
                            } else if let result = testResult {
                                Text(result)
                                    .foregroundStyle(result.hasPrefix("✓") ? Color.moss : Color.rust)
                            }
                        }
                    }
                    .disabled(input.isEmpty || isTesting)
                }

                if !serverURLString.isEmpty {
                    Section("Current") {
                        Text(serverURLString)
                            .foregroundStyle(Color.charcoal.opacity(0.6))
                    }
                }
            }
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        serverURLString = input
                        if let url = makeURL(from: input) {
                            connectionMonitor.start(url: url)
                        }
                        dismiss()
                    }
                    .disabled(input.isEmpty)
                }
            }
            .onAppear { input = serverURLString }
        }
    }

    private func testConnection() {
        guard let url = makeURL(from: input) else {
            testResult = "✗ Invalid URL"
            return
        }
        isTesting = true
        testResult = nil
        Task {
            do {
                let response = try await NetworkService().healthCheck(url)
                await MainActor.run {
                    testResult = "✓ Connected (v\(response.version))"
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    testResult = "✗ Not reachable"
                    isTesting = false
                }
            }
        }
    }

    private func makeURL(from string: String) -> URL? {
        let raw = string.hasPrefix("http") ? string : "http://\(string)"
        return URL(string: raw)
    }
}
