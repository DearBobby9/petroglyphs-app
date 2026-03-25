import SwiftUI

struct ServerSettingsSheet: View {
    @Environment(ConnectionMonitor.self) var connectionMonitor
    @Environment(\.dismiss) var dismiss
    @AppStorage("serverURLString") private var serverURLString: String = ""
    @AppStorage("localURLString") private var localURLString: String = ""
    @AppStorage("pairingCode") private var pairingCode: String = ""
    @AppStorage("connectionMode") private var connectionMode: String = "local"

    @State private var input: String = ""
    @State private var codeInput: String = ""
    @State private var testResult: String?
    @State private var isTesting = false
    @FocusState private var focusedField: Field?

    enum Field { case url, code }
    enum Mode: String, CaseIterable {
        case local = "local"
        case cloud = "cloud"
        var label: String { self == .local ? "Local" : "Cloud" }
    }

    private var selectedMode: Mode {
        Mode(rawValue: connectionMode) ?? .local
    }

    private let cloudURL = "https://web-production-d8b49.up.railway.app"

    private var canTest: Bool {
        guard !isTesting else { return false }
        return selectedMode == .cloud ? true : !input.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                // Mode Picker
                Section {
                    Picker("Mode", selection: $connectionMode) {
                        ForEach(Mode.allCases, id: \.rawValue) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                // ✅ Show only the relevant section based on mode
                if selectedMode == .local {
                    Section {
                        TextField("Local IP with\":3333\" like example below", text: $input)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($focusedField, equals: .url)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                    } header: {
                        Text("MCP Server URL")
                    } footer: {
                        Text("Enter the local IP address of your server, e.g. http://192.168.1.10:3333")
                    }
                } else {
                    Section {
                        TextField("e.g. A7K2", text: $codeInput)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                            .font(.system(.body, design: .monospaced))
                            .focused($focusedField, equals: .code)
                            .submitLabel(.done)
                            .onSubmit { focusedField = nil }
                    } header: {
                        Text("Pairing Code")
                    } footer: {
                        Text("Ask your AI to call get_pairing_code, then enter the 4-letter code to link your session.")
                    }
                }

                // Test Connection
                Section {
                    Button {
                        focusedField = nil
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
                    .disabled(!canTest)
                }

                if selectedMode == .local && !localURLString.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            connectionMonitor.stop()
                            serverURLString = ""
                            localURLString = ""
                            input = ""
                            testResult = nil
                        } label: {
                            Text("Disconnect")
                        }
                    }
                }

                if selectedMode == .cloud && !pairingCode.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            connectionMonitor.stop()
                            serverURLString = ""
                            pairingCode = ""
                            codeInput = ""
                            testResult = nil
                        } label: {
                            Text("Disconnect")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .animation(.default, value: connectionMode) // ✅ Smooth mode transitions
            .navigationTitle("Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        focusedField = nil
                        if selectedMode == .local {
                            localURLString = input
                            serverURLString = input
                            pairingCode = ""
                            if let url = makeURL(from: input) {
                                connectionMonitor.start(url: url)
                            }
                        } else {
                            serverURLString = cloudURL
                            pairingCode = codeInput.trimmingCharacters(in: .whitespaces).uppercased()
                            if let url = makeURL(from: cloudURL) {
                                connectionMonitor.start(url: url)
                            }
                        }
                        dismiss()
                    }
                    .disabled(selectedMode == .local ? input.isEmpty : codeInput.isEmpty)
                }
            }
            .onAppear {
                // Migrate: if localURLString is empty but serverURLString has a non-cloud URL, recover it
                if localURLString.isEmpty && !serverURLString.isEmpty && serverURLString != cloudURL {
                    localURLString = serverURLString
                }
                input = localURLString
                codeInput = pairingCode
            }
        }
    }

    private func testConnection() {
        switch selectedMode {
        case .local:
            guard let url = makeURL(from: input) else {
                testResult = "✗ Invalid URL"
                return
            }
            runHealthCheck(url: url)
        case .cloud:
            guard let url = makeURL(from: cloudURL) else { return }
            let code = codeInput.trimmingCharacters(in: .whitespaces).uppercased()
            isTesting = true
            testResult = nil
            Task {
                do {
                    try await NetworkService().validateCode(code, serverURL: url)
                    await MainActor.run {
                        testResult = "✓ Code valid"
                        isTesting = false
                    }
                } catch NetworkService.NetworkError.invalidCode {
                    await MainActor.run {
                        testResult = "✗ Invalid code"
                        isTesting = false
                    }
                } catch {
                    await MainActor.run {
                        testResult = "✗ Server unreachable"
                        isTesting = false
                    }
                }
            }
        }
    }

    private func runHealthCheck(url: URL) {
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
