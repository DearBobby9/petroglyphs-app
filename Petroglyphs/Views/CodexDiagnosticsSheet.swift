import SwiftUI
import UIKit

struct CodexDiagnosticsSheet: View {
    let target: CodexChatTarget
    @Environment(\.dismiss) private var dismiss
    @State private var model = CodexDiagnosticsModel()

    var body: some View {
        NavigationStack {
            List {
                Section("Target") {
                    LabeledContent("Machine", value: target.host.name)
                    LabeledContent("Chat", value: target.thread.displayTitle)
                }
                if let value = model.diagnostics {
                    Section("Builds") {
                        LabeledContent("App", value: value.app.version ?? "Unavailable")
                        LabeledContent("App commit", value: value.app.commit ?? "Not recorded")
                        LabeledContent("MCP version", value: value.mcp.version ?? "Unavailable")
                        LabeledContent("MCP build commit", value: value.mcp.buildCommit ?? "Not recorded")
                        LabeledContent("MCP source commit", value: value.mcp.sourceCommit ?? "Not recorded")
                        LabeledContent("ChatGPT Desktop", value: value.desktop.version ?? "Unavailable")
                        Text("Codex runs inside ChatGPT Desktop.").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Compatibility baseline") {
                        LabeledContent("Artifact comparison", value: value.compatibility.state)
                        if let reason = value.compatibility.reason { Text(reason).foregroundStyle(Color.rust) }
                        Text(value.compatibility.evidence).font(.caption).textSelection(.enabled)
                        Text("A matching version identifies the installed artifact. It does not verify host operations.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Observed host capabilities") {
                        LabeledContent("Read probe", value: value.host.probe.status)
                        if let operations = value.host.probe.operations { Text(operations.joined(separator: ", ")).font(.caption) }
                        ForEach(value.host.execution.keys.sorted(), id: \.self) { operation in
                            LabeledContent(operation, value: value.host.execution[operation] ?? "not_tested")
                        }
                        LabeledContent("Model catalogue", value: value.host.modelCatalog.status)
                        LabeledContent("Model source", value: value.host.modelCatalog.source ?? "Unavailable")
                    }
                    Section("Executables") {
                        ForEach(value.executables.keys.sorted(), id: \.self) { name in
                            if let executable = value.executables[name] {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(name).font(.headline)
                                    Text(executable.resolvedPath ?? executable.path).font(.caption.monospaced()).textSelection(.enabled)
                                    Text(executable.version ?? "Version unavailable").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Section {
                        Button("Copy diagnostic JSON", systemImage: "doc.on.doc") { UIPasteboard.general.string = value.formattedJSON }
                            .frame(minHeight: 44)
                    } footer: { Text("Observed \(value.observedAt)") }
                } else if model.isLoading {
                    ProgressView("Loading diagnostics…")
                } else if let error = model.error {
                    Text(error).foregroundStyle(Color.rust).textSelection(.enabled)
                }
            }
            .navigationTitle("Bridge diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.load(for: target) } }
                        .disabled(model.isLoading)
                }
            }
            .task(id: CodexConversationKey(target)) { await model.load(for: target) }
        }
    }
}
