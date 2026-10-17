import PencilKit
import SwiftUI

@Observable
@MainActor
final class CanvasViewModel {
    private var document: CanvasDocument
    private let storageURL: URL
    private var protectsUnreadableDocument = false
    private(set) var storageError: String?

    var drawing: PKDrawing {
        get { document.drawing }
        set {
            guard newValue != document.drawing else { return }
            document.drawing = newValue
            document.exportBounds = CanvasDocument.isValid(newValue.bounds) ? newValue.bounds : CanvasDocument.emptyBounds
            documentChanged()
        }
    }

    var background: CanvasBackground {
        get { document.background }
        set {
            guard newValue != document.background else { return }
            document.background = newValue
            documentChanged()
        }
    }

    var documentID: UUID { document.id }
    var revision: Int { document.revision }
    var exportBounds: CGRect { document.exportBounds }
    var snapshotFilename: String { "canvas-\(documentID.uuidString.lowercased())-r\(revision).png" }

    var showCastSuccess = false
    var showWipeAnimation = false
    var isCasting = false
    var castError: String?

    private var drawingStartTime: Date?
    private let exporter = CanvasExporter()

    init(storageURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.storageURL = storageURL ?? URL.applicationSupportDirectory
            .appending(path: "Petroglyphs/Canvas/active-canvas.json")
        let darkMode = defaults.bool(forKey: "darkModeEnabled")
        let fallback: CanvasBackground = darkMode ? .charcoal : .white
        let key = darkMode ? "darkCanvasBackgroundHex" : "canvasBackgroundHex"
        let background = defaults.string(forKey: key).flatMap(CanvasBackground.init(rawValue:)) ?? fallback
        document = CanvasDocument(background: background)

        if FileManager.default.fileExists(atPath: self.storageURL.path) {
            do {
                document = try JSONDecoder().decode(CanvasDocument.self, from: Data(contentsOf: self.storageURL))
            } catch {
                protectsUnreadableDocument = true
                storageError = "The saved canvas could not be opened. Its original file is preserved; current edits cannot be saved. \(error.localizedDescription)"
            }
        } else {
            save()
        }
    }

    @discardableResult
    func save() -> Bool {
        guard !protectsUnreadableDocument else { return false }
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(document).write(to: storageURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            storageError = nil
            return true
        } catch {
            storageError = "The canvas could not be saved. \(error.localizedDescription)"
            return false
        }
    }

    func snapshot() -> Data? {
        document.drawing.exportPNG(backgroundColor: document.background.uiColor, exportBounds: document.exportBounds)
    }

    private func documentChanged() {
        document.revision += 1
        save()
    }

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
        let documentSnapshot = document
        let payload: SubmissionPayload
        castError = nil
        do {
            // Export before starting async work so later drawing or chat edits cannot change this send.
            let export = try exporter.export(
                document: documentSnapshot,
                duration: duration
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

                isCasting = false
                showCastSuccess = true
            } catch {
                isCasting = false
                castError = error.localizedDescription
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
