import SwiftUI
import UIKit

struct CodexImagePreviewItem: Identifiable {
    let id: String
    let name: String
    let load: () async throws -> Data
}

struct CodexImagePreview: View {
    @Environment(\.dismiss) private var dismiss
    @State private var items: [CodexImagePreviewItem]
    @State private var selection: String
    let onRemove: ((String) -> Void)?

    init(items: [CodexImagePreviewItem], selectedID: String, onRemove: ((String) -> Void)? = nil) {
        _items = State(initialValue: items)
        _selection = State(initialValue: selectedID)
        self.onRemove = onRemove
    }

    private var selectedIndex: Int { items.firstIndex { $0.id == selection } ?? 0 }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(items) { item in
                    CodexImagePreviewPage(item: item).tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(Color.panelBackground)
            .navigationTitle(items.indices.contains(selectedIndex) ? items[selectedIndex].name : "Image")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Previous", systemImage: "chevron.left") { selection = items[selectedIndex - 1].id }
                        .disabled(selectedIndex == 0)
                    Spacer()
                    Text("\(min(selectedIndex + 1, items.count)) / \(items.count)").monospacedDigit()
                    Spacer()
                    Button("Next", systemImage: "chevron.right") { selection = items[selectedIndex + 1].id }
                        .disabled(selectedIndex + 1 >= items.count)
                }
                .font(.callout).padding(12).background(.regularMaterial)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if let onRemove {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Remove image", systemImage: "trash", role: .destructive) {
                            let index = selectedIndex
                            onRemove(selection)
                            items.removeAll { $0.id == selection }
                            if items.isEmpty { dismiss() }
                            else { selection = items[min(index, items.count - 1)].id }
                        }
                    }
                }
            }
        }
    }
}

private struct CodexImagePreviewPage: View {
    let item: CodexImagePreviewItem
    @State private var image: UIImage?
    @State private var error: String?

    var body: some View {
        Group {
            if let image { CodexZoomableImage(image: image).accessibilityLabel(item.name) }
            else if let error { ContentUnavailableView("Image unavailable", systemImage: "photo", description: Text(error)) }
            else { ProgressView("Loading image…") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: item.id) {
            do {
                let bytes = try await item.load()
                guard !Task.isCancelled else { return }
                guard let decoded = UIImage(data: bytes) else { throw CodexConversationStore.ConversationError.imageUnavailable }
                image = decoded
            } catch {
                guard !Task.isCancelled else { return }
                self.error = error.localizedDescription
            }
        }
    }
}

private struct CodexZoomableImage: UIViewRepresentable {
    let image: UIImage
    func makeUIView(context: Context) -> ImageZoomScrollView { ImageZoomScrollView(image: image) }
    func updateUIView(_ view: ImageZoomScrollView, context: Context) {}
}

private final class ImageZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView: UIImageView
    private var lastSize: CGSize = .zero

    init(image: UIImage) {
        imageView = UIImageView(image: image)
        super.init(frame: .zero)
        delegate = self
        backgroundColor = .clear
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        imageView.frame = CGRect(origin: .zero, size: image.size)
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
        isAccessibilityElement = true
        accessibilityHint = "Pinch to zoom, then drag to inspect. Double tap to zoom or fit."
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Zoom in", target: self, selector: #selector(zoomIn)),
            UIAccessibilityCustomAction(name: "Fit image", target: self, selector: #selector(fitImage))
        ]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize, bounds.width > 0, bounds.height > 0,
              let image = imageView.image else { centerImage(); return }
        let relativeScale = lastSize == .zero ? 1 : zoomScale / minimumZoomScale
        lastSize = bounds.size
        let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
        minimumZoomScale = fit
        maximumZoomScale = max(fit * 8, 1)
        zoomScale = min(maximumZoomScale, fit * relativeScale)
        centerImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
    private func centerImage() {
        contentInset = UIEdgeInsets(top: max(0, (bounds.height - contentSize.height) / 2), left: max(0, (bounds.width - contentSize.width) / 2), bottom: 0, right: 0)
    }
    @objc private func zoomIn() -> Bool { setZoomScale(min(maximumZoomScale, zoomScale * 2), animated: true); return true }
    @objc private func fitImage() -> Bool { setZoomScale(minimumZoomScale, animated: true); return true }
    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.1 { _ = fitImage() }
        else {
            let point = gesture.location(in: imageView)
            let scale = min(maximumZoomScale, minimumZoomScale * 3)
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}
