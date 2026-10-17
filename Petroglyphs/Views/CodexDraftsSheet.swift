import SwiftUI

struct CodexDraftsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let serverURL: URL?
    @State private var recovering: CodexCreationDraftSummary?
    @State private var recoveryError: String?
    let onStartIndependent: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Start another task", systemImage: "square.and.pencil") {
                        dismiss()
                        onStartIndependent()
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("chat.startIndependent")
                } footer: {
                    Text("Each task keeps its own draft and request. Closing a task does not cancel remote execution.")
                }
                Section("Drafts and pending requests") {
                    if appState.creationDrafts.isEmpty {
                        Text("No saved drafts or pending creation requests.").foregroundStyle(.secondary)
                    }
                    ForEach(appState.creationDrafts) { draft in
                        Button {
                            if draft.destination == nil { recovering = draft }
                            else { appState.resumeCreationDraft(draft); dismiss() }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(draft.displayTitle.isEmpty ? "Untitled draft" : draft.displayTitle).font(.headline).foregroundStyle(Color.charcoal)
                                if let destination = draft.destination {
                                    Label("\(destination.host.name) · \(destination.project.displayName)", systemImage: "folder")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text(draft.prompt).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                                HStack {
                                    Text(draft.state).font(.caption.weight(.semibold))
                                    Spacer()
                                    Text(draft.updatedAt, style: .relative).font(.caption)
                                }.foregroundStyle(.secondary)
                                if let error = draft.recoveryError {
                                    Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Color.rust)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(draft.state == "unreadable" || (draft.destination == nil && serverURL == nil))
                        .accessibilityIdentifier("chat.savedDraft.\(draft.id)")
                    }
                }
            }
            .navigationTitle("Drafts and pending")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { appState.refreshCreationDrafts() }
            .sheet(item: $recovering) { draft in
                if let serverURL {
                    CodexThreadPickerView(serverURL: serverURL, selection: .constant(nil), creationOnly: true,
                        onNewChat: { host, project in
                            do {
                                appState.newCodexChat = try CodexProjectCreationModel.recoverLegacyDraft(draft, project: project, host: host, serverURL: serverURL)
                                dismiss()
                            } catch { recoveryError = error.localizedDescription }
                        })
                }
            }
            .alert("Could not recover this draft", isPresented: Binding(get: { recoveryError != nil }, set: { if !$0 { recoveryError = nil } })) {
                Button("OK") { recoveryError = nil }
            } message: { Text(recoveryError ?? "") }
        }
    }
}
