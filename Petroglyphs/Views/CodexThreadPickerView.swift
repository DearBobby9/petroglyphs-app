import SwiftUI

struct CodexThreadPickerView: View {
    @Environment(AppState.self) private var appState
    let serverURL: URL
    @Binding var selection: CodexChatTarget?
    let creationOnly: Bool
    let onChoose: () -> Void
    let onNewChat: (CodexHost, CodexProject) -> Void
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

    init(serverURL: URL, selection: Binding<CodexChatTarget?>, creationOnly: Bool = false,
         initialHostID: String? = nil, onChoose: @escaping () -> Void = {},
         onNewChat: @escaping (CodexHost, CodexProject) -> Void) {
        self.serverURL = serverURL
        _selection = selection
        self.creationOnly = creationOnly
        self.onChoose = onChoose
        self.onNewChat = onNewChat
        _scope = State(initialValue: creationOnly ? .projects : .chats)
        _selectedHostID = State(initialValue: initialHostID)
    }

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
                if !creationOnly { scopePicker }
                searchField
                if !creationOnly { cachedChats }
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.limestone)
            .navigationTitle(creationOnly ? "New chat location" : "Choose a Codex chat")
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
                    CodexProjectChatsView(serverURL: serverURL, host: host, project: project, selection: selection,
                                          onChoose: { choose($0, host: host, project: project) },
                                          onNewChat: { beginDraft(project, host: host) })
                }
            }
            .onDisappear {
                paginationTask?.cancel()
            }
        }
        .tint(Color.burntOchre)
        .accessibilityIdentifier(creationOnly ? "codex.newChatProjectPicker" : "codex.threadPicker")
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

    private var cachedTargets: [CodexChatTarget] {
        appState.recentCodexChats.filter {
            $0.serverURL == serverURL && (searchText.isEmpty || $0.thread.displayTitle.localizedCaseInsensitiveContains(searchText))
        }
    }

    @ViewBuilder
    private var cachedChats: some View {
        if !cachedTargets.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent and cached chats").font(.caption.weight(.semibold))
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(cachedTargets, id: \.thread.id) { target in
                            Button {
                                selection = target
                                onChoose()
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(target.thread.displayTitle).font(.callout.weight(.semibold)).lineLimit(2)
                                    Text(target.host.name).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(width: 180, alignment: .leading).padding(10)
                                .background(Color.panelBackground, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("codex.cached.\(target.thread.id)")
                        }
                    }
                }
                Text("Cached chats can be read and edited offline. Sending requires a current connection.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
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
                Text(request.query.isEmpty ? "Choose a project to create a chat on this machine." : "Try another chat title or choose a project.")
            } actions: {
                Button("Refresh") { reloadID += 1 }
                    .buttonStyle(.bordered)
            }
            .overlay(alignment: .bottom) {
                Button("Choose project and start chat", systemImage: "square.and.pencil") { scope = .projects; searchText = "" }
                    .buttonStyle(.borderedProminent).frame(minHeight: 44).padding(20)
                    .accessibilityIdentifier("codex.emptyNewChat")
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
                        Button {
                            if creationOnly, let host = selectedHost { beginDraft(project, host: host) }
                            else { selectedProject = project }
                        } label: {
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
                        .disabled(creationOnly && !project.canCreate)
                        .accessibilityIdentifier("codex.project.\(project.id)")
                        .accessibilityAddTraits(selection?.projectId == project.id && selection?.host.id == selectedHostID ? .isSelected : [])
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Projects on \(selectedHost?.name ?? "selected location")")
                } footer: {
                    Text(creationOnly ? "Choose the project for your new chat. The first message creates it." : "Open a project to choose a chat or create a new one.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private func choose(_ thread: CodexThread, host: CodexHost, project: CodexProject? = nil) {
        selection = CodexChatTarget(thread: thread, serverURL: serverURL, host: host,
                                    projectId: project?.id ?? thread.projectId, projectName: project?.displayName ?? thread.projectName)
        onChoose()
        dismiss()
    }

    private func beginDraft(_ project: CodexProject, host: CodexHost) {
        guard project.canCreate, host.canSelect else { return }
        onNewChat(host, project)
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
                self.selection = CodexChatTarget(thread: selection.thread, serverURL: selection.serverURL, host: host, projectId: selection.projectId, projectName: selection.projectName)
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
    let onNewChat: () -> Void
    @State private var model = CodexThreadListModel()
    @State private var search = ""
    @State private var reloadID = 0
    @State private var paginationTask: Task<Void, Never>?

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
                Button(action: onNewChat) {
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
                        CodexPickerThreadRow(thread: thread, isSelected: isSelected(thread), projectName: project.displayName)
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
    var projectName: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(thread.displayTitle)
                    .font(.headline)
                    .foregroundStyle(Color.charcoal)
                    .lineLimit(3)
                if let name = projectName ?? thread.projectName {
                    Label(name, systemImage: "folder").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if !thread.cwd.isEmpty {
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
