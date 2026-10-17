import SwiftUI

struct CodexDraftsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
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
                            appState.resumeCreationDraft(draft)
                            dismiss()
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
                        .disabled(draft.destination == nil || draft.recoveryError != nil)
                        .accessibilityIdentifier("chat.savedDraft.\(draft.id)")
                    }
                }
            }
            .navigationTitle("Drafts and pending")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { appState.refreshCreationDrafts() }
        }
    }
}
