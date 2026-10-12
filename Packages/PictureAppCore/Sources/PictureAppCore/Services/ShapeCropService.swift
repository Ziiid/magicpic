import CoreGraphics
import CoreImage
import Foundation

/// Positionerar/beskär till en vald form. Två separata steg, medvetet
/// hållna isär (se `positioned(_:image:transform:)` och
/// `applyingSilhouette(_:to:)`):
///
/// `SearchViewModel.applyPipeline` positionerar numera motivets
/// GENOMSKINLIGA urklipp i kanvasen INNAN bakgrunden läggs på (så en vald
/// bakgrundsfärg/bild kan fylla HELA kanvasen, oavsett var motivet råkar
/// vara panorerat - se `buggs.md`), och lägger först sedan formens
/// siluett (cirkel/hexagon/...) över den FÄRDIGA kompositen. `apply(_:to:
/// transform:)` finns kvar oförändrad som en bekvämlighetsmetod som gör
/// båda stegen i ett svep, mot en REDAN kompositerad bild (motiv+bakgrund
/// ihopslaget) - fortfarande använd av `ShapePickerView`s
/// formförhandsvisningar, som inte har någon anledning att hålla isär
/// motiv och bakgrund.
public struct ShapeCropService {
    public struct ShapeError: LocalizedError {
        let message: String
        // Se `BackgroundRemovalService.RemovalError`s motsvarande kommentar.
        public var errorDescription: String? {
            String(localized: String.LocalizationValue(message), bundle: .module, locale: AppLanguage.current.locale)
        }
    }

    public init() {}

    /// Kanvasens storlek för en given preset/källstorlek - den största
    /// rektangeln med `preset.aspectRatio` som får plats centrerat i
    /// `sourceSize` (en "cover"-beskärning till bildförhållandet), eller
    /// källans egna mått oförändrade om `aspectRatio` är `nil` (bara
    /// Rektangel - ingen formbeskärning alls). Generaliserar den tidigare
    /// hårdkodade `min(bredd,höjd)`-kvadraten, som var specialfallet
    /// `aspectRatio == 1` (verifierat: samma resultat för det fallet).
    public static func canvasSize(for preset: ShapePreset, sourceSize: CGSize) -> CGSize {
        guard let aspectRatio = preset.aspectRatio, sourceSize.width > 0, sourceSize.height > 0 else { return sourceSize }
        let sourceAspect = sourceSize.width / sourceSize.height
        return sourceAspect > aspectRatio
            ? CGSize(width: sourceSize.height * aspectRatio, height: sourceSize.height)
            : CGSize(width: sourceSize.width, height: sourceSize.width / aspectRatio)
    }

    /// Positionerar `image` (pan/zoom/rotation från `transform`) in i
    /// kanvasen för `preset` - bara beskärningen till rätt bildförhållande,
    /// INGEN formsiluett (cirkel/hexagon/...) läggs på här.
    /// `allowsExposedEdges: true` - se `CanvasTransform.scaledToFill`s
    /// dokumentation - en kant får medvetet lämnas genomskinlig;
    /// anropsstället ansvarar för att fylla den (bakgrunden, komponerad
    /// separat i kanvasens storlek).
    public func positioned(_ preset: ShapePreset, image: PlatformImage, transform: CanvasTransform = .identity) throws -> PlatformImage {
        guard preset.aspectRatio != nil else { return image }

        guard let cgImage = image.cgImageRepresentation else {
            throw ShapeError(message: "Kunde inte läsa bilddata.")
        }

        let original = CIImage(cgImage: cgImage)
        let canvasSize = Self.canvasSize(for: preset, sourceSize: image.size)
        let squared = transform.scaledToFill(original, target: CGRect(origin: .zero, size: canvasSize), allowsExposedEdges: true)
        return try Self.render(squared, size: canvasSize)
    }

    /// Klipper en REDAN kanvas-formad bild (se `positioned(_:image:
    /// transform:)` eller en annan bild med samma mått) till formens
    /// siluett. No-op för `.square`/`.rectangle` - de är redan rektanglar
    /// (oavsett bildförhållande), ingen extra mask behövs.
    public func applyingSilhouette(_ shape: OutputShape, freeform: FreeformPath? = nil, to image: PlatformImage) throws -> PlatformImage {
        guard shape != .square, shape != .rectangle else { return image }
        // Frihand utan ritad kontur (ännu) = ingen klippning.
        if shape == .freeform, freeform?.isUsable != true { return image }

        guard let cgImage = image.cgImageRepresentation else {
            throw ShapeError(message: "Kunde inte läsa bilddata.")
        }

        let squared = CIImage(cgImage: cgImage)
        let canvasSize = squared.extent.size

        guard let maskCGImage = Self.rasterizeMask(for: shape, freeform: freeform, size: canvasSize) else {
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

    /// Positionerar OCH klipper siluetten i ETT svep, mot en REDAN
    /// kompositerad bild (motiv+bakgrund ihopslaget) - se filens
    /// dokumentation för varför `SearchViewModel.applyPipeline` inte
    /// längre använder den här för slutresultatet (bakgrunden skulle då
    /// bara fylla den positionerade bildens egna gränser, inte hela
    /// kanvasen). Fortfarande använd av `ShapePickerView`s
    /// formförhandsvisningar.
    ///
    /// - Parameter transform: Användarens pan/zoom av motivet inom duken.
    ///   `.identity` ger en centrerad beskärning.
    public func apply(_ preset: ShapePreset, to image: PlatformImage, transform: CanvasTransform = .identity) throws -> PlatformImage {
        try applyingSilhouette(preset.contour, freeform: preset.freeform, to: try positioned(preset, image: image, transform: transform))
    }

    private static func render(_ ciImage: CIImage, size: CGSize) throws -> PlatformImage {
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: CGRect(origin: .zero, size: size)) else {
            throw ShapeError(message: "Kunde inte rendera resultatet.")
        }
        return PlatformImage(cgImageRepresentation: cgImage)
    }

    private static func rasterizeMask(for shape: OutputShape, freeform: FreeformPath?, size: CGSize) -> CGImage? {
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
        if shape == .freeform, let freeform {
            context.addPath(freeform.cgPath(in: rect))
        } else {
            context.addPath(shape.cgPath(in: rect))
        }
        context.fillPath()
        return context.makeImage()
    }
}
