import AppKit
import Observation

/// Mutable state of one open image edit: the base bitmap, the annotations drawn
/// over it, and an undo history.
///
/// Image-only by design. The text pane keeps a plain `String` and inherits undo
/// from the `NSTextView` behind SwiftUI's `TextEditor`.
@MainActor
@Observable
final class ImageEditorDocument {

    static let undoLimit = 30

    private struct Snapshot {
        let baseImage: NSImage
        let annotations: [ImageAnnotation]
    }

    private(set) var baseImage: NSImage
    private(set) var annotations: [ImageAnnotation] = []
    private(set) var hasUnsavedChanges = false

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var cachedPixelatedBase: NSImage?

    init(baseImage: NSImage) {
        self.baseImage = baseImage
    }

    var pixelSize: CGSize { baseImage.pixelSize }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Pixelated copy of the current base image, used to render redactions.
    /// Computed once per base image.
    var pixelatedBase: NSImage? {
        if let cachedPixelatedBase { return cachedPixelatedBase }
        cachedPixelatedBase = ImageTransformService.pixelated(baseImage)
        return cachedPixelatedBase
    }

    // MARK: - Mutations

    func add(_ annotation: ImageAnnotation) {
        checkpoint()
        annotations.append(annotation)
    }

    /// Flattens current annotations into the base image, then applies
    /// `transform` to the result. Any geometric change goes through here — that
    /// is what keeps annotation coordinates meaningful after a crop or rotate.
    func applyTransform(_ transform: (NSImage) -> NSImage?) {
        guard let flattenedImage = flattened(), let transformed = transform(flattenedImage) else { return }
        checkpoint()
        annotations = []
        baseImage = transformed
        cachedPixelatedBase = nil
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(Snapshot(baseImage: baseImage, annotations: annotations))
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(Snapshot(baseImage: baseImage, annotations: annotations))
        restore(next)
    }

    func flattened() -> NSImage? {
        AnnotationRenderer.flatten(
            baseImage: baseImage,
            pixelatedBase: pixelatedBase,
            annotations: annotations,
            pixelSize: pixelSize
        )
    }

    // MARK: - Private

    private func checkpoint() {
        undoStack.append(Snapshot(baseImage: baseImage, annotations: annotations))
        if undoStack.count > Self.undoLimit {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
        hasUnsavedChanges = true
    }

    private func restore(_ snapshot: Snapshot) {
        baseImage = snapshot.baseImage
        annotations = snapshot.annotations
        cachedPixelatedBase = nil
        hasUnsavedChanges = !undoStack.isEmpty
    }
}
