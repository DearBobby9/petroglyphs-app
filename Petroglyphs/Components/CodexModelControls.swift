import SwiftUI

struct CodexModelControls: View {
    let model: CodexModelSettingsModel
    let selection: CodexDraftModelSelection?
    var isNewChat = false
    var isLocked = false
    var hasImages = false
    let onChange: (CodexDraftModelSelection?) -> Void
    let onRefresh: () -> Void

    private var selectedModel: CodexAvailableModel? { selection.flatMap { model.model(named: $0.model) } }
    private var modelTitle: String {
        guard let selection else { return isNewChat ? "Host defaults" : "Follow chat settings" }
        return selectedModel?.displayName ?? selection.model
    }
    private var effortTitle: String {
        guard let selection else { return "Automatic" }
        return selection.reasoningEffort?.capitalized ?? "Choose effort"
    }
    private var catalogueAvailable: Bool { model.catalogue?.status == "available" && model.selectionUnavailableReason == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    Menu { modelOptions } label: { controlLabel(modelTitle) }
                        .accessibilityLabel("Model")
                        .accessibilityValue(modelTitle)
                        .accessibilityIdentifier("chat.modelSelector")
                    Menu { effortOptions } label: { controlLabel(effortTitle) }
                        .disabled(selection == nil)
                        .accessibilityLabel("Reasoning effort")
                        .accessibilityValue(effortTitle)
                        .accessibilityIdentifier("chat.effortSelector")
                    Spacer(minLength: 0)
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(minWidth: 340, alignment: .leading)
                Menu {
                    Section("Model") { modelOptions }
                    if selection != nil { Section("Reasoning effort") { effortOptions } }
                } label: {
                    controlLabel(selection == nil ? modelTitle : "\(modelTitle) · \(effortTitle)", compact: true)
                }
                .accessibilityLabel("Model and reasoning effort")
                .accessibilityValue("\(modelTitle), \(effortTitle)")
                .accessibilityIdentifier("chat.modelSettings")
            }
            .disabled(isLocked)

            if model.isLoading {
                Label("Loading model settings…", systemImage: "arrow.clockwise")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let reason = model.validationMessage(for: selection, hasImages: hasImages), !isLocked {
                Text(reason).font(.caption).foregroundStyle(Color.rust)
                    .accessibilityIdentifier("chat.modelValidation")
            } else if selection == nil {
                if let settings = model.settings, let currentModel = settings.model {
                    Text("Current: \(model.model(named: currentModel)?.displayName ?? currentModel)\(settings.reasoningEffort.map { " · \($0.capitalized)" } ?? ""). Follows settings when the message runs.")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("chat.observedSettings")
                } else {
                    Text(isNewChat ? "Uses this location’s defaults when the chat starts." : "Uses this chat’s settings when the message runs.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let reason = model.selectionUnavailableReason ?? model.error {
                    Text(reason).font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("chat.modelsUnavailable")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func controlLabel(_ title: String, compact: Bool = false) -> some View {
        HStack(spacing: 5) {
            Text(title).lineLimit(1).truncationMode(.middle)
            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
        }
        .font(.caption.weight(.medium))
        .frame(minHeight: 44)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .foregroundStyle(Color.charcoal)
        .frame(maxWidth: compact ? .infinity : nil, alignment: .leading)
    }

    @ViewBuilder
    private var modelOptions: some View {
        Button {
            onChange(nil)
        } label: {
            Label(isNewChat ? "Use host defaults" : "Follow chat settings", systemImage: selection == nil ? "checkmark" : "arrow.turn.down.right")
        }
        .accessibilityIdentifier("chat.model.follow")
        if catalogueAvailable, let catalogue = model.catalogue {
            ForEach(catalogue.models, id: \.model) { option in
                Button {
                    let retainedEffort = selection?.reasoningEffort.flatMap { effort in
                        option.supportedReasoningEfforts.contains { $0.reasoningEffort == effort } ? effort : nil
                    }
                    onChange(CodexDraftModelSelection(model: option.model, reasoningEffort: retainedEffort))
                } label: {
                    Label(option.displayName, systemImage: selection?.model == option.model ? "checkmark" : "circle")
                }
                .accessibilityIdentifier("chat.model.\(option.model)")
            }
        } else if let reason = model.selectionUnavailableReason {
            Text(reason)
        }
        Divider()
        Button("Refresh models", systemImage: "arrow.clockwise", action: onRefresh)
            .disabled(model.isLoading)
            .accessibilityIdentifier("chat.refreshModels")
    }

    @ViewBuilder
    private var effortOptions: some View {
        if catalogueAvailable, let selectedModel {
            ForEach(selectedModel.supportedReasoningEfforts, id: \.reasoningEffort) { option in
                Button {
                    onChange(CodexDraftModelSelection(model: selectedModel.model, reasoningEffort: option.reasoningEffort))
                } label: {
                    Label(option.reasoningEffort.capitalized, systemImage: selection?.reasoningEffort == option.reasoningEffort ? "checkmark" : "circle")
                }
                .accessibilityIdentifier("chat.effort.\(option.reasoningEffort)")
            }
        } else {
            Text(model.selectionUnavailableReason ?? "Choose an available model first.")
        }
    }
}
