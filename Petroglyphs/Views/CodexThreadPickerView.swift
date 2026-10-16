import SwiftUI

struct CodexThreadPickerView: View {
    let serverURL: URL
    @Binding var selection: CodexChatTarget?
    @Environment(\.dismiss) private var dismiss
    @State private var model = CodexThreadListModel()
    @State private var projects = CodexProjectListModel()
    @State private var scope = Scope.chats
    @State private var selectedProject: CodexProject?
    @State private var searchText = ""
    @State private var reloadID = 0
    @State private var paginationTask: Task<Void, Never>?
    @State private var hosts: [CodexHost] = []
    @State private var selectedHostID: String?
    @State private var isLoadingHosts = true
    @State private var hostError: String?
    @State private var hostsReloadID = 0
    @State private var hostsVersion = 0

    private enum Scope: String, CaseIterable {
        case chats = "All chats"
        case projects = "Projects"
    }

    private struct SearchRequest: Equatable {
        let scope: Scope
        let hostId: String?
        let hostsVersion: Int
        let query: String
        let reloadID: Int
    }

    private var request: SearchRequest {
        SearchRequest(scope: scope, hostId: selectedHostID, hostsVersion: hostsVersion, query: searchText.trimmingCharacters(in: .whitespacesAndNewlines), reloadID: reloadID)
    }

    private var selectedHost: CodexHost? {
        hosts.first { $0.id == selectedHostID }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                hostPicker
                scopePicker
                searchField
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.limestone)
            .navigationTitle("Choose a Codex chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if selectedProject == nil {
                        Button { hostsReloadID += 1 } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .disabled(isLoadingHosts)
                        .accessibilityIdentifier("codex.refresh")
                    }
                }
            }
            .task(id: request) {
                paginationTask?.cancel()
                guard scope == .chats, let host = selectedHost, host.canSelect else { return }
                await model.load(from: serverURL, hostId: host.id, search: request.query)
            }
            .task(id: "\(selectedHostID ?? "")-\(hostsVersion)-\(reloadID)-\(scope.rawValue)") {
                guard scope == .projects, let host = selectedHost, host.canSelect else { return }
                await projects.load(from: serverURL, hostId: host.id)
            }
            .task(id: hostsReloadID) { await loadHosts() }
            .onChange(of: scope) { _, _ in searchText = "" }
            .navigationDestination(item: $selectedProject) { project in
                if let host = selectedHost {
                    CodexProjectChatsView(serverURL: serverURL, host: host, project: project, selection: selection) { thread in
                        choose(thread, host: host)
                    }
                }
            }
            .onDisappear {
                paginationTask?.cancel()
            }
        }
        .tint(Color.burntOchre)
    }

    private var hostPicker: some View {
        Menu {
            ForEach(["local", "remote"], id: \.self) { kind in
                Section(kind == "local" ? "This Mac" : "Remote connections") {
                    ForEach(hosts.filter { $0.kind == kind }) { host in
                        Button {
                            guard host.id != selectedHostID else { return }
                            selectedHostID = host.id
                            selectedProject = nil
                            searchText = ""
                        } label: {
                            if host.canSelect {
                                Label(host.name, systemImage: host.id == selectedHostID ? "checkmark" : "desktopcomputer")
                            } else {
                                Label("\(host.name) · Unavailable", systemImage: "network.slash")
                            }
                        }
                        .accessibilityIdentifier("codex.host.\(host.id)")
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "desktopcomputer")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat location")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                    Text(selectedHost?.name ?? "Choose a chat location")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.charcoal)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.panelBackground, in: RoundedRectangle(cornerRadius: 10))
        }
        .disabled(isLoadingHosts || hosts.isEmpty)
        .accessibilityIdentifier("codex.hostSelector")
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var scopePicker: some View {
        Picker("Browse", selection: $scope) {
            ForEach(Scope.allCases, id: \.self) { scope in Text(scope.rawValue).tag(scope) }
        }
        .pickerStyle(.segmented)
        .frame(minHeight: 44)
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .accessibilityIdentifier("codex.scope")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(scope == .chats ? "Search chat titles" : "Search projects", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel(scope == .chats ? "Search Codex chats" : "Search Codex projects")
                .accessibilityIdentifier("codex.search")
                .disabled(selectedHost?.canSelect != true || isLoadingHosts)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color.panelBackground, in: RoundedRectangle(cornerRadius: 10))
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if isLoadingHosts {
            ProgressView("Loading chat locations…")
        } else if let hostError {
            ContentUnavailableView {
                Label("Could not load locations", systemImage: "network.slash")
            } description: {
                Text(hostError)
            } actions: {
                Button("Retry") { hostsReloadID += 1 }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("codex.hostRetry")
            }
        } else if selectedHost?.canSelect != true {
            ContentUnavailableView {
                Label(selectedHost == nil ? "Choose a chat location" : "Location unavailable", systemImage: "network.slash")
            } description: {
                Text(selectedHost?.unavailabilityReason ?? "Select a location to load its chats.")
            } actions: {
                Button("Refresh locations") { hostsReloadID += 1 }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("codex.locationRetry")
            }
            .accessibilityIdentifier("codex.locationUnavailable")
        } else if scope == .projects {
            projectsContent
        } else if model.isLoading || model.hostId != selectedHostID {
            ProgressView("Loading chats…")
                .accessibilityIdentifier("codex.loading")
        } else if let error = model.error {
            ContentUnavailableView {
                Label("Could not load chats", systemImage: "exclamationmark.bubble")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { reloadID += 1 }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("codex.retry")
            }
            .accessibilityIdentifier("codex.error")
        } else if model.threads.isEmpty {
            ContentUnavailableView {
                Label("No chats found", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text(request.query.isEmpty ? "Open a Codex chat at this location, then refresh." : "Try another chat title.")
            } actions: {
                Button("Refresh") { reloadID += 1 }
                    .buttonStyle(.bordered)
            }
            .accessibilityIdentifier("codex.empty")
        } else {
            threadList
        }
    }

    @ViewBuilder
    private var projectsContent: some View {
        if projects.isLoading || projects.hostId != selectedHostID {
            ProgressView("Loading projects…")
                .accessibilityIdentifier("codex.projectsLoading")
        } else if let error = projects.error {
            ContentUnavailableView {
                Label("Could not load projects", systemImage: "folder.badge.questionmark")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { reloadID += 1 }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("codex.projectsRetry")
            }
        } else if projects.matching(searchText).isEmpty {
            ContentUnavailableView {
                Label("No projects found", systemImage: "folder")
            } description: {
                Text(searchText.isEmpty ? "Add a project in Codex at this location, then refresh." : "Try another project name or folder path.")
            } actions: {
                Button("Refresh") { reloadID += 1 }
                    .buttonStyle(.bordered)
            }
            .accessibilityIdentifier("codex.projectsEmpty")
        } else {
            List {
                Section {
                    ForEach(projects.matching(searchText)) { project in
                        Button { selectedProject = project } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder")
                                    .foregroundStyle(Color.burntOchre)
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(project.displayName)
                                        .font(.headline)
                                        .foregroundStyle(Color.charcoal)
                                    Text(project.path)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                        .truncationMode(.middle)
                                    if !project.canCreate, let reason = project.reason {
                                        Text(reason).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .accessibilityHidden(true)
                            }
                            .frame(minHeight: 44)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("codex.project.\(project.id)")
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Projects on \(selectedHost?.name ?? "selected location")")
                } footer: {
                    Text("Open a project to choose a chat or create a new one.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func choose(_ thread: CodexThread, host: CodexHost) {
        selection = CodexChatTarget(thread: thread, serverURL: serverURL, host: host)
        dismiss()
    }

    private var threadList: some View {
        List {
            Section {
                ForEach(model.threads) { thread in
                    Button {
                        guard let host = selectedHost, host.canSelect else { return }
                        choose(thread, host: host)
                    } label: {
                        threadRow(thread)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("codex.thread.\(thread.id)")
                    .accessibilityAddTraits(isSelected(thread) ? [.isSelected] : [])
                }
            } header: {
                Text("Chats on \(selectedHost?.name ?? "selected location")")
            } footer: {
                Text("Messages and drawings go to the selected chat until you choose another.")
            }

            if let error = model.paginationError {
                Section {
                    Text(error)
                        .foregroundStyle(Color.rust)
                    Button("Retry loading more") { loadMore() }
                        .accessibilityIdentifier("codex.moreRetry")
                }
            } else if model.nextCursor != nil {
                Section {
                    Button(action: loadMore) {
                        HStack {
                            Text("Load more chats")
                            Spacer()
                            if model.isLoadingMore { ProgressView() }
                        }
                    }
                    .disabled(model.isLoadingMore)
                    .accessibilityIdentifier("codex.loadMore")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private func threadRow(_ thread: CodexThread) -> some View {
        CodexPickerThreadRow(thread: thread, isSelected: isSelected(thread))
    }

    private func isSelected(_ thread: CodexThread) -> Bool {
        selection?.serverURL == serverURL && selection?.host.id == selectedHostID && selection?.thread.id == thread.id
    }

    private func loadHosts() async {
        isLoadingHosts = true
        hostError = nil
        defer { isLoadingHosts = false }
        do {
            let result = try await NetworkService().codexHosts(from: serverURL)
            guard !Task.isCancelled else { return }
            hosts = result
            if let selection, selection.serverURL == serverURL {
                let host = result.first { $0.id == selection.host.id } ?? CodexHost(
                    id: selection.host.id,
                    name: selection.host.name,
                    kind: selection.host.kind,
                    configured: false,
                    available: false,
                    reason: "This chat location is no longer available. Reconnect it in Codex, then refresh."
                )
                if !hosts.contains(where: { $0.id == host.id }) { hosts.append(host) }
                self.selection = CodexChatTarget(thread: selection.thread, serverURL: selection.serverURL, host: host)
            }
            hostsVersion += 1
            if selectedHostID == nil {
                if let selection, selection.serverURL == serverURL {
                    selectedHostID = selection.host.id
                } else {
                    selectedHostID = result.first { $0.kind == "local" && $0.canSelect }?.id
                        ?? result.first { $0.canSelect }?.id
                        ?? result.first?.id
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            hostError = error.localizedDescription
        }
    }

    private func loadMore() {
        paginationTask?.cancel()
        paginationTask = Task { await model.loadMore() }
    }
}

private struct CodexProjectChatsView: View {
    let serverURL: URL
    let host: CodexHost
    let project: CodexProject
    let selection: CodexChatTarget?
    let onChoose: (CodexThread) -> Void
    @State private var model = CodexThreadListModel()
    @State private var search = ""
    @State private var reloadID = 0
    @State private var paginationTask: Task<Void, Never>?
    @State private var creationProject: CodexProject?

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Label(host.name, systemImage: "desktopcomputer")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.charcoal)
                Text(project.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button { creationProject = project } label: {
                    Label("New chat in this project", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .disabled(!host.canSelect || !project.canCreate)
                .accessibilityIdentifier("codex.newChat")
                if !project.canCreate {
                    Text(project.reason ?? "Creating chats is unavailable for this project.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("codex.creationUnavailable")
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Search chats in this project", text: $search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .accessibilityLabel("Search project chats")
                        .accessibilityIdentifier("codex.projectSearch")
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color.panelBackground, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(16)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color.limestone)
        .navigationTitle(project.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { reloadID += 1 } label: { Label("Refresh project chats", systemImage: "arrow.clockwise") }
                    .disabled(model.isLoading)
                    .accessibilityIdentifier("codex.projectRefresh")
            }
        }
        .task(id: "\(search)-\(reloadID)") {
            paginationTask?.cancel()
            await model.load(from: serverURL, hostId: host.id, projectId: project.id, search: search.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        .onDisappear { paginationTask?.cancel() }
        .sheet(item: $creationProject) { project in
            CodexCreateChatView(project: project, host: host, serverURL: serverURL, onCreated: onChoose)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading {
            ProgressView("Loading project chats…")
                .accessibilityIdentifier("codex.projectChatsLoading")
        } else if let error = model.error {
            ContentUnavailableView {
                Label("Could not load chats", systemImage: "exclamationmark.bubble")
            } description: {
                Text(error)
            } actions: {
                Button("Retry") { reloadID += 1 }.buttonStyle(.borderedProminent)
            }
            .accessibilityIdentifier("codex.projectChatsError")
        } else if model.threads.isEmpty {
            ContentUnavailableView {
                Label(search.isEmpty ? "No chats in this project" : "No chats found", systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text(search.isEmpty ? "Create a chat above to start a conversation here." : "Try another chat title.")
            }
            .accessibilityIdentifier("codex.projectChatsEmpty")
        } else {
            List {
                ForEach(model.threads) { thread in
                    Button { onChoose(thread) } label: {
                        CodexPickerThreadRow(thread: thread, isSelected: isSelected(thread))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("codex.thread.\(thread.id)")
                    .accessibilityAddTraits(isSelected(thread) ? [.isSelected] : [])
                }
                if let error = model.paginationError {
                    Section {
                        Text(error).foregroundStyle(Color.rust)
                        Button("Retry loading more", action: loadMore)
                            .frame(minHeight: 44)
                    }
                } else if model.nextCursor != nil {
                    Button(action: loadMore) {
                        HStack {
                            Text("Load more chats")
                            Spacer()
                            if model.isLoadingMore { ProgressView() }
                        }
                        .frame(minHeight: 44)
                    }
                    .disabled(model.isLoadingMore)
                    .accessibilityIdentifier("codex.projectLoadMore")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func isSelected(_ thread: CodexThread) -> Bool {
        selection?.serverURL == serverURL && selection?.host.id == host.id && selection?.thread.id == thread.id
    }

    private func loadMore() {
        paginationTask?.cancel()
        paginationTask = Task { await model.loadMore() }
    }
}

private struct CodexPickerThreadRow: View {
    let thread: CodexThread
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(thread.displayTitle)
                    .font(.headline)
                    .foregroundStyle(Color.charcoal)
                    .lineLimit(3)
                if !thread.cwd.isEmpty {
                    Text(thread.cwd)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(Date(timeIntervalSince1970: thread.updatedAt), format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.burntOchre)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct CodexCreateChatView: View {
    let onCreated: (CodexThread) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var model: CodexProjectCreationModel

    init(project: CodexProject, host: CodexHost, serverURL: URL, onCreated: @escaping (CodexThread) -> Void) {
        self.onCreated = onCreated
        _model = State(initialValue: CodexProjectCreationModel(project: project, host: host, serverURL: serverURL))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    Label(model.project.displayName, systemImage: "folder")
                        .font(.headline)
                    LabeledContent("Location", value: model.host.name)
                    Text(model.project.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Section {
                    TextField("Name (optional)", text: $model.title)
                        .textInputAutocapitalization(.sentences)
                        .disabled(model.request != nil)
                        .accessibilityLabel("New chat name, optional")
                        .accessibilityIdentifier("codex.chatName")
                    if model.title.utf16.count > 120 {
                        Text("Use 120 characters or fewer.").foregroundStyle(Color.rust)
                    }
                } header: {
                    Text("Chat name")
                }
                Section {
                    ZStack(alignment: .topLeading) {
                        if model.prompt.isEmpty {
                            Text("Write the first message to start this chat.")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                        }
                        TextEditor(text: $model.prompt)
                            .frame(minHeight: 140)
                            .scrollContentBackground(.hidden)
                            .disabled(model.request != nil)
                            .accessibilityLabel("First message")
                            .accessibilityIdentifier("codex.firstMessage")
                    }
                    if model.prompt.utf16.count > 20_000 {
                        Text("Use 20,000 characters or fewer.").foregroundStyle(Color.rust)
                    }
                } header: {
                    Text("Message")
                } footer: {
                    Text("Start chat creates a conversation in this project and sends this message. You can add drawings and images afterward.")
                }
                if model.request == nil {
                    Section {
                        Button { Task { await model.submit() } } label: {
                            Label("Start chat", systemImage: "arrow.up.message")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(!model.canSubmit)
                        .accessibilityIdentifier("codex.createChat")
                    }
                }
                if let status = model.status {
                    Section {
                        HStack(spacing: 12) {
                            if model.isBusy { ProgressView() }
                            Text(status)
                        }
                        .accessibilityIdentifier("codex.creationStatus")
                        if let notice = model.receipt?.notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                        if model.createdThread == nil {
                            Button("Check status") { Task { await model.checkStatus() } }
                                .frame(minHeight: 44)
                                .disabled(model.isBusy)
                                .accessibilityIdentifier("codex.checkCreation")
                        }
                        if model.canRetryOriginal {
                            Button("Retry this request") { Task { await model.retryOriginal() } }
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("codex.retryCreation")
                        }
                        if model.canEditFailedAttempt {
                            Button("Edit and try again") { model.editFailedAttempt() }
                                .frame(minHeight: 44)
                                .accessibilityIdentifier("codex.editFailedCreation")
                        }
                    }
                }
                if let error = model.storageError ?? model.error {
                    Section {
                        Text(error).foregroundStyle(Color.rust)
                            .accessibilityIdentifier("codex.creationError")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.limestone)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("New chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.request == nil ? "Cancel" : "Done") { dismiss() }
                        .disabled(model.isSubmitting)
                }
            }
            .interactiveDismissDisabled(model.isSubmitting)
            .task {
                if model.request != nil && model.createdThread == nil { await model.checkStatus() }
            }
            .task(id: model.receipt?.state) {
                guard model.receipt?.state.isActive == true else { return }
                // Poll only a recorded request. A timeout never initiates another POST.
                for _ in 0..<15 {
                    do { try await Task.sleep(for: .seconds(2)) } catch { return }
                    guard model.receipt?.state.isActive == true, !Task.isCancelled else { return }
                    await model.checkStatus()
                }
            }
            .onChange(of: model.createdThread, initial: true) { _, thread in
                guard let thread else { return }
                model.acknowledgeCompletion()
                onCreated(thread)
                dismiss()
            }
        }
        .tint(Color.burntOchre)
    }
}
