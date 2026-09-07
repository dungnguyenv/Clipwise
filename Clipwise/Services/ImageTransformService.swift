import AppKit
import CoreImage

/// Pixel-exact image transforms.
///
/// Rects are in **image pixel space with a top-left origin**, matching
/// `ImageAnnotation` coordinates. CGContext is bottom-left, so every function
/// that takes a rect flips it explicitly.
enum ImageTransformService {

    static func crop(_ image: NSImage, to rect: CGRect) -> NSImage? {
        guard let cgImage = image.cgImageAtNativeSize() else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let target = rect.integral.intersection(bounds)
        guard !target.isNull, target.width >= 1, target.height >= 1 else { return nil }

        return render(width: Int(target.width), height: Int(target.height)) { context in
            // Offset the full image so `target` lands at the context origin.
            context.draw(cgImage, in: CGRect(
                x: -target.origin.x,
                y: -(bounds.height - target.origin.y - target.height),
                width: bounds.width,
                height: bounds.height
            ))
        }
    }

    /// `+90` rotates counter-clockwise, `-90` clockwise. Only right angles.
    static func rotate(_ image: NSImage, degrees: CGFloat) -> NSImage? {
        guard let cgImage = image.cgImageAtNativeSize() else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        return render(width: cgImage.height, height: cgImage.width) { context in
            context.translateBy(x: height / 2, y: width / 2)
            context.rotate(by: degrees * .pi / 180)
            context.draw(cgImage, in: CGRect(x: -width / 2, y: -height / 2, width: width, height: height))
        }
    }

    static func flip(_ image: NSImage, horizontal: Bool) -> NSImage? {
        guard let cgImage = image.cgImageAtNativeSize() else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        return render(width: cgImage.width, height: cgImage.height) { context in
            if horizontal {
                context.translateBy(x: width, y: 0)
                context.scaleBy(x: -1, y: 1)
            } else {
                context.translateBy(x: 0, y: height)
                context.scaleBy(x: 1, y: -1)
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    static func resize(_ image: NSImage, to size: CGSize) -> NSImage? {
        guard let cgImage = image.cgImageAtNativeSize() else { return nil }
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())

        return render(width: width, height: height) { context in
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        }
    }

    /// Used by redact annotations. `blockSize` defaults to 1/40th of the
    /// smaller dimension, never below 8px.
    static func pixelated(_ image: NSImage, blockSize: CGFloat? = nil) -> NSImage? {
        guard let cgImage = image.cgImageAtNativeSize() else { return nil }
        let extent = CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height))
        let scale = blockSize ?? max(8, min(extent.width, extent.height) / 40)

        guard let filter = CIFilter(name: "CIPixellate", parameters: [
            kCIInputImageKey: CIImage(cgImage: cgImage),
            kCIInputScaleKey: scale,
            kCIInputCenterKey: CIVector(x: 0, y: 0),
        ]), let output = filter.outputImage,
            let result = CIContext(options: nil).createCGImage(output, from: extent)
        else { return nil }

        return makeImage(from: result, width: cgImage.width, height: cgImage.height)
    }

    // MARK: - Private

    private static func render(width: Int, height: Int, _ body: (CGContext) -> Void) -> NSImage? {
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.interpolationQuality = .high
        body(context)

        guard let output = context.makeImage() else { return nil }
        return makeImage(from: output, width: width, height: height)
    }

    /// Wraps a CGImage in an NSImage that carries a real NSBitmapImageRep, so
    /// `NSImage.pixelSize` and `pngData()` report native pixels.
    private static func makeImage(from cgImage: CGImage, width: Int, height: Int) -> NSImage {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = NSSize(width: width, height: height)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
