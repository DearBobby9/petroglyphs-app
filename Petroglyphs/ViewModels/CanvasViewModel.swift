import PencilKit
import SwiftUI

@Observable
@MainActor
final class CanvasViewModel {
    private var document: CanvasDocument
    private let storageURL: URL
    private var protectsUnreadableDocument = false
    private(set) var storageError: String?
    private var undoDrawings: [PKDrawing] = []
    private var redoDrawings: [PKDrawing] = []
    private var lastDrawingGestureID: UUID?

    var drawing: PKDrawing {
        get { document.drawing }
        set { updateDrawing(newValue) }
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
    var canUndo: Bool { !undoDrawings.isEmpty }
    var canRedo: Bool { !redoDrawings.isEmpty }

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

    private func documentChanged(saveImmediately: Bool = true) {
        document.revision += 1
        if saveImmediately { save() }
    }

    // One tool gesture can deliver several drawing updates, including a final
    // update after tool-up. Keep its first snapshot as the undo boundary.
    func updateDrawing(_ drawing: PKDrawing, gestureID: UUID? = nil, saveImmediately: Bool = true) {
        guard drawing != document.drawing else { return }
        if gestureID == nil || gestureID != lastDrawingGestureID {
            undoDrawings.append(document.drawing)
            if undoDrawings.count > 100 { undoDrawings.removeFirst() }
            redoDrawings.removeAll()
        }
        lastDrawingGestureID = gestureID
        replaceDrawing(drawing, saveImmediately: saveImmediately)
    }

    func undo() {
        guard let previous = undoDrawings.popLast() else { return }
        redoDrawings.append(document.drawing)
        lastDrawingGestureID = nil
        replaceDrawing(previous)
    }

    func redo() {
        guard let next = redoDrawings.popLast() else { return }
        undoDrawings.append(document.drawing)
        lastDrawingGestureID = nil
        replaceDrawing(next)
    }

    private func replaceDrawing(_ drawing: PKDrawing, saveImmediately: Bool = true) {
        document.drawing = drawing
        document.exportBounds = CanvasDocument.isValid(drawing.bounds) ? drawing.bounds : CanvasDocument.emptyBounds
        if !drawing.strokes.isEmpty { onFirstStroke() }
        documentChanged(saveImmediately: saveImmediately)
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
        guard !drawing.strokes.isEmpty else { return }
        drawing = PKDrawing()
        showWipeAnimation = true
        drawingStartTime = nil
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            showWipeAnimation = false
        }
    }
}
