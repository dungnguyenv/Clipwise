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

    /// The image the document was opened with, captured once and never
    /// mutated. Used only to detect whether `baseImage` has since been
    /// replaced by a transform.
    private let originalBaseImage: NSImage

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var cachedPixelatedBase: NSImage?

    init(baseImage: NSImage) {
        self.baseImage = baseImage
        self.originalBaseImage = baseImage
    }

    var pixelSize: CGSize { baseImage.pixelSize }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// True when the document differs from the image it was opened with —
    /// either annotations have been added, or `baseImage` has been replaced
    /// by a transform. Derived from the actual state rather than from
    /// undo-stack emptiness: once the stack has been capped, an empty stack
    /// no longer implies "back at the original," so that derivation could
    /// report clean while annotations (or a transformed base image) were
    /// still present. Identity (`!==`), not equality, is the right test —
    /// undoing a transform restores the very same `NSImage` instance the
    /// document started with.
    var hasUnsavedChanges: Bool {
        !annotations.isEmpty || baseImage !== originalBaseImage
    }

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
    ///
    /// Returns `false` when flattening or `transform` itself returned `nil`,
    /// in which case the document is left untouched. Callers that want to
    /// surface that failure to the user (rather than have the toolbar button
    /// silently do nothing) should check the return value.
    @discardableResult
    func applyTransform(_ transform: (NSImage) -> NSImage?) -> Bool {
        guard let flattenedImage = flattened(), let transformed = transform(flattenedImage) else { return false }
        checkpoint()
        annotations = []
        baseImage = transformed
        cachedPixelatedBase = nil
        return true
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
    }

    private func restore(_ snapshot: Snapshot) {
        baseImage = snapshot.baseImage
        annotations = snapshot.annotations
        cachedPixelatedBase = nil
    }
}
