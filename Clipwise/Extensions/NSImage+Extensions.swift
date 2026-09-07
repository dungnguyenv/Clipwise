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

extension NSImage {
    /// The largest bitmap representation, rasterizing first if the image is
    /// vector-backed. Everything pixel-exact goes through this.
    var bitmapRep: NSBitmapImageRep? {
        let bitmaps = representations.compactMap { $0 as? NSBitmapImageRep }
        if let largest = bitmaps.max(by: { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }) {
            return largest
        }
        guard let tiff = tiffRepresentation else { return nil }
        return NSBitmapImageRep(data: tiff)
    }

    /// Native pixel dimensions. `size` is in points, so on a Retina screenshot
    /// it reports half the real resolution — never use it for pixel math.
    /// Falls back to `size` (points, not pixels) only when the image has no
    /// bitmap representations and no TIFF data to rasterize — i.e. a degenerate
    /// `NSImage` with nothing drawable, whose `size` is typically `.zero`.
    var pixelSize: CGSize {
        guard let rep = bitmapRep else { return size }
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    func pngData() -> Data? {
        bitmapRep?.representation(using: .png, properties: [:])
    }
}
