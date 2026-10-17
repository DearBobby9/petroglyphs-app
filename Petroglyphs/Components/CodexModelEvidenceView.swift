import SwiftUI

struct CodexModelEvidenceView: View {
    let selection: CodexModelSelection
    let evidence: CodexModelEvidence?
    let verification: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("Requested: \(selection.model) · \(selection.reasoningEffort.capitalized)")
            if let evidence, verification == "confirmed" || verification == "different" {
                Text("\(verification == "confirmed" ? "Verified" : "Actual"): \(evidence.model)\(evidence.reasoningEffort.map { " · \($0.capitalized)" } ?? " · effort not reported")")
                ForEach(Array(evidence.reroutes.enumerated()), id: \.offset) { _, reroute in
                    Text("\(reroute.fromModel) → \(reroute.toModel): \(reroute.reason)")
                }
            } else {
                Text(verification == "unverified" ? "Actual model was not verified." : "Actual model is not confirmed yet.")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }
}
