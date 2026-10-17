import SwiftUI

struct ServerSettingsSheet: View {
    @Environment(ConnectionMonitor.self) private var connectionMonitor
    @Environment(BridgeDiscoveryModel.self) private var discovery
    @Environment(\.dismiss) private var dismiss
    @AppStorage("serverURLString") private var serverURLString: String = ""
    @AppStorage("localURLString") private var localURLString: String = ""
    @AppStorage("pairingCode") private var pairingCode: String = ""
    @AppStorage("connectionMode") private var savedConnectionMode: String = "local"

    @State private var input: String = ""
    @State private var codeInput: String = ""
    @State private var editingMode: Mode = .local
    @State private var pendingDisconnect = false
    @State private var hasLoadedSettings = false
    @State private var testGeneration = UUID()
    @State private var testTask: Task<Void, Never>?
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var showAdvancedAddress = false
    @FocusState private var focusedField: Field?

    enum Field { case url, code }
    enum Mode: String, CaseIterable {
        case local = "local"
        case cloud = "cloud"
        var label: String { self == .local ? "Paired Mac" : "Legacy cloud" }
    }

    private let cloudURL = "https://web-production-d8b49.up.railway.app"

    private struct TestSnapshot: Equatable {
        let mode: Mode
        let normalizedURL: String
        let code: String
        let pendingDisconnect: Bool
    }

    private var testSnapshot: TestSnapshot? {
        let urlString = editingMode == .local ? input : cloudURL
        guard let url = makeURL(from: urlString) else { return nil }
        return TestSnapshot(
            mode: editingMode,
            normalizedURL: url.absoluteString,
            code: codeInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
            pendingDisconnect: pendingDisconnect
        )
    }

    private var canTest: Bool {
        guard !isTesting, testSnapshot != nil else { return false }
        return editingMode == .cloud || !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canSave: Bool {
        if pendingDisconnect { return true }
        guard testSnapshot != nil else { return false }
        return editingMode == .local || !codeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canDisconnect: Bool {
        switch editingMode {
        case .local:
            return !localURLString.isEmpty || (!serverURLString.isEmpty && serverURLString != cloudURL)
        case .cloud:
            return !pairingCode.isEmpty || serverURLString == cloudURL
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Mode", selection: $editingMode) {
                        ForEach(Mode.allCases, id: \.rawValue) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                if editingMode == .local {
                    Section {
                        DiscoveredMacsView()
                    } footer: {
                        Text("Keep Tailscale connected on the iPad and Mac. Approve a new Mac once. Use Connect to switch between saved Macs.")
                    }
                    if connectionMonitor.serverURL != nil {
                        Section("Connection") {
                            LabeledContent("Bridge Mac", value: connectionMonitor.bridgeName ?? "Paired Mac")
                            LabeledContent("Status", value: connectionMonitor.isConnected ? "Connected" : (connectionMonitor.isReconnecting ? "Reconnecting" : "Disconnected"))
                            LabeledContent("Route", value: connectionMonitor.transportDescription)
                                .accessibilityIdentifier("connection.transport")
                                .accessibilityValue(connectionMonitor.transportDescription)
                            if let endpoint = connectionMonitor.activeEndpoint {
                                LabeledContent("Mac address", value: endpoint.absoluteString)
                                    .font(.subheadline)
                                    .accessibilityIdentifier("connection.endpoint")
                                    .accessibilityValue(endpoint.absoluteString)
                            }
                            Text(connectionMonitor.recoveryDescription)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("connection.recovery")
                                .accessibilityValue(connectionMonitor.backupReady ? "Backup address saved" : "Backup unavailable")
                            if let checked = connectionMonitor.lastVerifiedAt {
                                LabeledContent("Last verified") { Text(checked, style: .time) }
                            }
                            Text("The route above connects this iPad to the bridge. Choose the Codex execution machine separately in the chat picker.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        DisclosureGroup("Existing paired address", isExpanded: $showAdvancedAddress) {
                            TextField("Paired Mac URL", text: $input)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .focused($focusedField, equals: .url)
                                .submitLabel(.done)
                                .onSubmit { focusedField = nil }
                        }
                    } header: {
                        Text("Advanced")
                    } footer: {
                        Text("For an existing paired URL or custom installation. This address contains a private pairing credential. Automatic discovery does not need manual address entry.")
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
                        Text("Legacy submission service. This route does not select a remote Codex machine. Use a paired Mac for Codex conversations.")
                    }
                }

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

                if canDisconnect {
                    Section {
                        Button(role: .destructive) {
                            pendingDisconnect.toggle()
                        } label: {
                            Label("Disconnect", systemImage: pendingDisconnect ? "checkmark.circle.fill" : "xmark.circle")
                        }
                        .accessibilityValue(pendingDisconnect ? "Pending save" : "Not selected")
                        .accessibilityHint(pendingDisconnect ? "Tap again to cancel disconnect." : "Disconnects when you save.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .animation(.default, value: editingMode)
            .navigationTitle("Connect to Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        invalidateTest()
                        if discovery.pairingBridge != nil { discovery.cancelPairing() }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        focusedField = nil
                        saveConnection()
                        dismiss()
                    }
                    .disabled(!canSave || discovery.pairingBridge != nil)
                }
            }
            .onAppear(perform: loadFormState)
            .onDisappear {
                invalidateTest()
                if discovery.pairingBridge != nil { discovery.cancelPairing() }
            }
            .onChange(of: input) { _, _ in invalidateTest() }
            .onChange(of: codeInput) { _, _ in invalidateTest() }
            .onChange(of: editingMode) { _, _ in
                pendingDisconnect = false
                invalidateTest()
            }
            .onChange(of: pendingDisconnect) { _, _ in invalidateTest() }
            .onChange(of: discovery.connectionRevision) { _, _ in
                if let url = discovery.pairedURL {
                    input = url.absoluteString
                    pendingDisconnect = false
                }
            }
        }
    }

    private func loadFormState() {
        guard !hasLoadedSettings else { return }
        hasLoadedSettings = true
        editingMode = Mode(rawValue: savedConnectionMode) ?? .local

        let existingLocalURL = localURLString.isEmpty && !serverURLString.isEmpty && serverURLString != cloudURL
            ? serverURLString
            : localURLString
        input = existingLocalURL
        codeInput = pairingCode
    }

    private func saveConnection() {
        invalidateTest()

        if pendingDisconnect {
            savedConnectionMode = editingMode.rawValue
            serverURLString = ""
            if editingMode == .local {
                localURLString = ""
            } else {
                pairingCode = ""
            }
            connectionMonitor.stop()
            return
        }

        switch editingMode {
        case .local:
            guard let url = makeURL(from: input) else { return }
            savedConnectionMode = editingMode.rawValue
            localURLString = url.absoluteString
            serverURLString = url.absoluteString
            pairingCode = ""
            connectionMonitor.start(url: url)
        case .cloud:
            guard let url = makeURL(from: cloudURL) else { return }
            let code = codeInput.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !code.isEmpty else { return }
            savedConnectionMode = editingMode.rawValue
            serverURLString = url.absoluteString
            pairingCode = code
            connectionMonitor.start(url: url)
        }
    }

    private func testConnection() {
        guard let snapshot = testSnapshot else {
            testResult = "✗ Invalid URL"
            return
        }

        let generation = testGeneration
        isTesting = true
        testResult = nil
        testTask = Task { @MainActor in
            let result: String
            do {
                guard let url = URL(string: snapshot.normalizedURL) else {
                    result = "✗ Invalid URL"
                    finishTest(result, generation: generation, snapshot: snapshot)
                    return
                }
                switch snapshot.mode {
                case .local:
                    let response = try await NetworkService().healthCheck(url)
                    result = "✓ Connected (v\(response.version))"
                case .cloud:
                    try await NetworkService().validateCode(snapshot.code, serverURL: url)
                    result = "✓ Code valid"
                }
            } catch NetworkService.NetworkError.invalidCode {
                result = "✗ Invalid code"
            } catch {
                result = snapshot.mode == .local ? "✗ Not reachable" : "✗ Server unreachable"
            }
            finishTest(result, generation: generation, snapshot: snapshot)
        }
    }

    @MainActor
    private func finishTest(_ result: String, generation: UUID, snapshot: TestSnapshot) {
        guard !Task.isCancelled,
              generation == testGeneration,
              snapshot == testSnapshot else { return }
        testResult = result
        isTesting = false
        testTask = nil
    }

    private func invalidateTest() {
        testGeneration = UUID()
        testTask?.cancel()
        testTask = nil
        testResult = nil
        isTesting = false
    }

    private func makeURL(from string: String) -> URL? {
        let value = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let lowercasedValue = value.lowercased()
        if (lowercasedValue.hasPrefix("http:") && !lowercasedValue.hasPrefix("http://")) ||
            (lowercasedValue.hasPrefix("https:") && !lowercasedValue.hasPrefix("https://")) {
            return nil
        }

        let hasScheme = value.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*://"#, options: .regularExpression) != nil
        let candidate = hasScheme ? value : "http://\(value)"
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return components.url
    }
}
