import Vision
import CoreImage

/// Klipper ut motivet helt på enheten med Apples Vision-ramverk
/// (VNGenerateForegroundInstanceMaskRequest) och kompositerar det mot valfri
/// bakgrund. Kräver ingen nätverksuppkoppling eller extern tjänst och är i
/// regel klart på under en sekund. Fungerar identiskt på macOS och iOS.
///
/// Masken (den dyra Vision-analysen) och kompositeringen (billig,
/// CoreImage-filter) är medvetet separata metoder: att byta bakgrundsstil
/// upprepade gånger på samma bild ska inte behöva köra Vision-analysen på
/// nytt varje gång.
public struct BackgroundRemovalService {
    public struct RemovalError: LocalizedError {
        let message: String
        public var errorDescription: String? { message }
    }

    /// Resultatet av Vision-analysen för en bild: originalet plus masken för
    /// motivet. Kan återanvändas för att kompositera mot flera olika
    /// bakgrunder utan att analysera bilden på nytt.
    public struct ForegroundMask {
        let original: CGImage
        let mask: CVPixelBuffer

        public init(original: CGImage, mask: CVPixelBuffer) {
            self.original = original
            self.mask = mask
        }
    }

    /// Vad urklippet ska läggas mot.
    public enum BackgroundStyle {
        case transparent
        case color(CGColor)
        case blurredOriginal(radius: Double = 30)
        case custom(PlatformImage, transform: CanvasTransform = .identity)
    }

    public init() {}

    /// Kör Vision-analysen och hittar motivets mask. Det här är den dyra
    /// delen (typiskt under en sekund, men fortfarande värt att cacha om
    /// användaren bara byter bakgrund).
    public func generateMask(for image: PlatformImage) throws -> ForegroundMask {
        guard let cgImage = image.cgImageRepresentation else {
            throw RemovalError(message: "Kunde inte läsa bilddata.")
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let result = request.results?.first else {
            throw RemovalError(message: "Vision kunde inte analysera bilden.")
        }

        guard !result.allInstances.isEmpty else {
            throw RemovalError(message: "Hittade inget tydligt motiv att lyfta ur bakgrunden.")
        }

        let maskPixelBuffer = try result.generateScaledMaskForImage(
            forInstances: result.allInstances,
            from: handler
        )

        return ForegroundMask(original: cgImage, mask: maskPixelBuffer)
    }

    /// Lägger motivet från en redan beräknad mask mot vald bakgrund. Billig
    /// nog att köras varje gång användaren byter bakgrundsstil.
    public func composite(_ foreground: ForegroundMask, background: BackgroundStyle) throws -> PlatformImage {
        let originalCI = CIImage(cgImage: foreground.original)
        let maskCI = CIImage(cvPixelBuffer: foreground.mask)
        let backgroundCI = try makeBackgroundImage(background, original: originalCI)

        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            throw RemovalError(message: "Kunde inte skapa bildfilter.")
        }
        blendFilter.setValue(originalCI, forKey: kCIInputImageKey)
        blendFilter.setValue(backgroundCI, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(maskCI, forKey: kCIInputMaskImageKey)

        guard let outputCIImage = blendFilter.outputImage else {
            throw RemovalError(message: "Kunde inte skapa resultatbilden.")
        }

        let context = CIContext()
        guard let outputCGImage = context.createCGImage(outputCIImage, from: originalCI.extent) else {
            throw RemovalError(message: "Kunde inte rendera resultatet.")
        }

        return PlatformImage(cgImageRepresentation: outputCGImage)
    }

    private func makeBackgroundImage(_ style: BackgroundStyle, original: CIImage) throws -> CIImage {
        let extent = original.extent

        switch style {
        case .transparent:
            return CIImage(color: .clear).cropped(to: extent)

        case .color(let cgColor):
            return CIImage(color: CIColor(cgColor: cgColor)).cropped(to: extent)

        case .blurredOriginal(let radius):
            guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
                throw RemovalError(message: "Kunde inte skapa oskärpefilter.")
            }
            // Bilden kläms fast över hela ytan innan oskärpan, annars blir
            // kanterna genomskinliga eftersom CIGaussianBlur läser utanför
            // bildens ursprungliga gränser.
            blurFilter.setValue(original.clampedToExtent(), forKey: kCIInputImageKey)
            blurFilter.setValue(radius, forKey: kCIInputRadiusKey)
            guard let blurred = blurFilter.outputImage?.cropped(to: extent) else {
                throw RemovalError(message: "Kunde inte skapa oskärpan.")
            }
            return blurred

        case .custom(let customImage, let transform):
            guard let customCG = customImage.cgImageRepresentation else {
                throw RemovalError(message: "Kunde inte läsa den valda bakgrundsbilden.")
            }
            return Self.scaledToFill(CIImage(cgImage: customCG), target: extent, transform: transform)
        }
    }

    /// Skalar och beskär `image` så den täcker `target` helt (aspect fill),
    /// justerad med användarens extra zoom/panorering. `transform.scale`
    /// klampas till minst 1 - att zooma UT under "cover"-nivån skulle
    /// blotta kanter utan bildinnehåll. Beskärningsfönstret klampas i sin
    /// tur till att alltid ligga innanför den skalade bilden, så en
    /// panorering aldrig kan dra fram tomma kanter (även om `transform`
    /// råkar ange ett värde utanför giltigt intervall).
    private static func scaledToFill(_ image: CIImage, target: CGRect, transform: CanvasTransform) -> CIImage {
        let baseScale = max(target.width / image.extent.width, target.height / image.extent.height)
        let scale = baseScale * max(transform.scale, 1)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let centeredX = (scaled.extent.width - target.width) / 2
        let centeredY = (scaled.extent.height - target.height) / 2
        // `offset` är en andel av målytan; CoreImages y-axel pekar uppåt,
        // SwiftUIs nedåt, därav minustecknet på Y.
        let panX = transform.offset.width * target.width
        let panY = -transform.offset.height * target.height

        let maxX = max(scaled.extent.width - target.width, 0)
        let maxY = max(scaled.extent.height - target.height, 0)
        let cropX = min(max(centeredX - panX, 0), maxX)
        let cropY = min(max(centeredY - panY, 0), maxY)

        let cropOrigin = CGPoint(x: scaled.extent.minX + cropX, y: scaled.extent.minY + cropY)
        let cropped = scaled.cropped(to: CGRect(origin: cropOrigin, size: target.size))
        return cropped.transformed(by: CGAffineTransform(translationX: target.minX - cropOrigin.x, y: target.minY - cropOrigin.y))
    }
}
