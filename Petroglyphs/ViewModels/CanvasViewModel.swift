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

    func cast(combo: Combo?, networkService: NetworkService, offlineQueue: OfflineQueue, serverURL: URL?, isConnected: Bool, pairingCode: String? = nil) {
        guard !drawing.strokes.isEmpty else { return }

        let duration = drawingStartTime.map { Date().timeIntervalSince($0) * 1000 } ?? 0
        isCasting = true

        Task {
            do {
                let export = try exporter.export(drawing: drawing, duration: duration)
                let code = pairingCode?.isEmpty == false ? pairingCode : nil
                let payload = SubmissionPayload(
                    image: export.imageBase64,
                    strokeMetadata: export.strokeMetadata,
                    combo: combo,
                    pairingCode: code
                )

                if isConnected, let url = serverURL {
                    try await networkService.submit(payload, to: url)
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
