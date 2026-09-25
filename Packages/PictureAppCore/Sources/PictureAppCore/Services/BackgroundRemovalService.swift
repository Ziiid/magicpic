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
    ///
    /// - Parameter foregroundImage: Motivets pixeldata att kompositera -
    ///   default `foreground.original` (bilden masken beräknades från).
    ///   Skickas in separat när bildkorrigeringar (`ImageAdjustments`) ska
    ///   synas i resultatet: masken (dyr, Vision) cachas mot den OJUSTERADE
    ///   bilden, men själva urklippet ska ändå visa den JUSTERADE - masken
    ///   är fortfarande giltig eftersom justeringar inte ändrar motivets
    ///   geometri/kontur, bara dess färger.
    public func composite(_ foreground: ForegroundMask, background: BackgroundStyle, foregroundImage: CGImage? = nil) throws -> PlatformImage {
        let originalCI = CIImage(cgImage: foregroundImage ?? foreground.original)
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
            return transform.scaledToFill(CIImage(cgImage: customCG), target: extent)
        }
    }
}
