import PencilKit
import SwiftUI

@Observable
class CanvasViewModel {
    var drawing = PKDrawing()
    var showCastSuccess = false
    var showWipeAnimation = false
    var isCasting = false
    var castError: String?

    private var drawingStartTime: Date?
    private let exporter = CanvasExporter()

    func onFirstStroke() {
        if drawingStartTime == nil {
            drawingStartTime = Date()
        }
    }

    func cast(
        combo: Combo?,
        networkService: NetworkService,
        offlineQueue: OfflineQueue,
        serverURL: URL?,
        isConnected: Bool,
        pairingCode: String? = nil,
        codexTarget: CodexChatTarget? = nil,
        requiresCodexThread: Bool = false,
        backgroundColor: UIColor = .white,
        onSubmission: ((SubmissionResponse, SubmissionPayload) -> Void)? = nil
    ) {
        guard !isCasting, !drawing.strokes.isEmpty else { return }
        if requiresCodexThread {
            guard let codexTarget, !codexTarget.thread.id.isEmpty, codexTarget.serverURL == serverURL else {
                castError = "Choose a Codex chat before sending."
                return
            }
            guard isConnected, serverURL != nil else {
                castError = "Reconnect to your Mac before sending to Codex."
                return
            }
            guard codexTarget.host.canSelect else {
                castError = codexTarget.host.unavailabilityReason
                return
            }
        }

        let duration = drawingStartTime.map { Date().timeIntervalSince($0) * 1000 } ?? 0
        let drawingSnapshot = drawing
        let backgroundSnapshot = backgroundColor
            .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            .withAlphaComponent(1)
        let payload: SubmissionPayload
        castError = nil
        do {
            // Export before starting async work so later drawing or chat edits cannot change this send.
            let export = try exporter.export(
                drawing: drawingSnapshot,
                duration: duration,
                backgroundColor: backgroundSnapshot
            )
            let code = pairingCode?.isEmpty == false ? pairingCode : nil
            payload = SubmissionPayload(
                image: export.imageBase64,
                strokeMetadata: export.strokeMetadata,
                combo: combo,
                pairingCode: code,
                threadId: codexTarget?.thread.id,
                hostId: codexTarget?.host.id
            )
        } catch {
            castError = error.localizedDescription
            return
        }
        isCasting = true

        Task {
            do {
                if isConnected, let url = serverURL {
                    let receipt = try await networkService.submit(payload, to: url)
                    onSubmission?(receipt, payload)
                } else {
                    offlineQueue.enqueue(payload)
                }

                await MainActor.run {
                    isCasting = false
                    showCastSuccess = true
                }
            } catch {
                await MainActor.run {
                    isCasting = false
                    castError = error.localizedDescription
                }
            }
        }
    }

    func clear() {
        showWipeAnimation = true
        drawingStartTime = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.drawing = PKDrawing()
            self.showWipeAnimation = false
        }
    }
}
