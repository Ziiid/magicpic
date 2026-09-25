import CoreGraphics
import CoreImage

/// Beskär och maskerar den redan färdigt kompositerade bilden (motiv +
/// bakgrund) till en vald form. Körs som ett sista steg EFTER
/// `BackgroundRemovalService` - det påverkar bara slutresultatets kontur,
/// inte själva urklippet eller bakgrundsvalet.
public struct ShapeCropService {
    public struct ShapeError: LocalizedError {
        let message: String
        public var errorDescription: String? { message }
    }

    public init() {}

    /// - Parameter transform: Användarens pan/zoom av motivet inom den
    ///   kvadratiska duken, satt via `ImagePositionerView`. `.identity` ger
    ///   en centrerad kvadratisk beskärning, precis som tidigare.
    public func apply(_ shape: OutputShape, to image: PlatformImage, transform: CanvasTransform = .identity) throws -> PlatformImage {
        guard shape != .rectangle else { return image }

        guard let cgImage = image.cgImageRepresentation else {
            throw ShapeError(message: "Kunde inte läsa bilddata.")
        }

        let original = CIImage(cgImage: cgImage)
        let side = min(original.extent.width, original.extent.height)
        let canvasSize = CGSize(width: side, height: side)
        let squared = transform.scaledToFill(original, target: CGRect(origin: .zero, size: canvasSize))

        guard shape != .square else {
            return try Self.render(squared, size: canvasSize)
        }

        guard let maskCGImage = Self.rasterizeMask(for: shape, size: canvasSize) else {
            throw ShapeError(message: "Kunde inte skapa formens mask.")
        }

        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            throw ShapeError(message: "Kunde inte skapa bildfilter.")
        }
        blendFilter.setValue(squared, forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage(color: .clear).cropped(to: squared.extent), forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(CIImage(cgImage: maskCGImage), forKey: kCIInputMaskImageKey)

        guard let output = blendFilter.outputImage else {
            throw ShapeError(message: "Kunde inte tillämpa formen.")
        }
        return try Self.render(output, size: canvasSize)
    }

    private static func render(_ ciImage: CIImage, size: CGSize) throws -> PlatformImage {
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: CGRect(origin: .zero, size: size)) else {
            throw ShapeError(message: "Kunde inte rendera resultatet.")
        }
        return PlatformImage(cgImageRepresentation: cgImage)
    }

    private static func rasterizeMask(for shape: OutputShape, size: CGSize) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        let rect = CGRect(origin: .zero, size: size)
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(rect)
        context.setFillColor(gray: 1, alpha: 1)
        context.addPath(shape.cgPath(in: rect))
        context.fillPath()
        return context.makeImage()
    }
}
