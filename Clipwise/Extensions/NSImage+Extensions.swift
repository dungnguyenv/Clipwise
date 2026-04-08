import AppKit

extension NSImage {
    /// Generate a thumbnail of the given size, preserving aspect ratio
    func thumbnail(maxSize: CGFloat) -> NSImage {
        let aspectRatio = size.width / size.height
        let targetSize: NSSize

        if aspectRatio > 1 {
            targetSize = NSSize(width: maxSize, height: maxSize / aspectRatio)
        } else {
            targetSize = NSSize(width: maxSize * aspectRatio, height: maxSize)
        }

        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0
        )
        thumbnail.unlockFocus()
        return thumbnail
    }
}
