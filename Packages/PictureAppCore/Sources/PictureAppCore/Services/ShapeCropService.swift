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

    public func apply(_ shape: OutputShape, to image: PlatformImage) throws -> PlatformImage {
        guard shape != .rectangle else { return image }

        guard let cgImage = image.cgImageRepresentation else {
            throw ShapeError(message: "Kunde inte läsa bilddata.")
        }

        let original = CIImage(cgImage: cgImage)
        let squareExtent = Self.centeredSquare(in: original.extent)
        let squared = original
            .cropped(to: squareExtent)
            .transformed(by: CGAffineTransform(translationX: -squareExtent.minX, y: -squareExtent.minY))
        let side = squareExtent.width
        let canvasSize = CGSize(width: side, height: side)

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

    private static func centeredSquare(in extent: CGRect) -> CGRect {
        let side = min(extent.width, extent.height)
        return CGRect(
            x: extent.minX + (extent.width - side) / 2,
            y: extent.minY + (extent.height - side) / 2,
            width: side,
            height: side
        )
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
        context.addPath(path(for: shape, in: rect))
        context.fillPath()
        return context.makeImage()
    }

    private static func path(for shape: OutputShape, in rect: CGRect) -> CGPath {
        switch shape {
        case .rectangle, .square:
            return CGPath(rect: rect, transform: nil)
        case .roundedSquare:
            let corner = rect.width * 0.18
            return CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
        case .circle:
            return CGPath(ellipseIn: rect, transform: nil)
        case .hexagon:
            return regularPolygonPath(sides: 6, in: rect)
        case .octagon:
            return regularPolygonPath(sides: 8, in: rect)
        }
    }

    /// En regelbunden N-hörning inskriven i `rect`, roterad så den alltid
    /// får en platt sida längst upp och ner (t.ex. en "stopptecken"-oktagon)
    /// istället för en spets.
    private static func regularPolygonPath(sides: Int, in rect: CGRect) -> CGPath {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let angleOffset = -CGFloat.pi / 2 + (.pi / CGFloat(sides))

        let path = CGMutablePath()
        for i in 0..<sides {
            let angle = angleOffset + (2 * .pi * CGFloat(i) / CGFloat(sides))
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
