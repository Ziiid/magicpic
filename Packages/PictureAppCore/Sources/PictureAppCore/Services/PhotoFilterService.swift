import CoreImage

/// Tillämpar en färdig bildstil (`PhotoFilter`) på en bild, ren CoreImage -
/// körs INNAN `ImageAdjustments` och Vision-analysen (se
/// `SearchViewModel.removeBackground()`), som ett första, valfritt
/// "stil"-lager. Bygger uteslutande på Apples inbyggda CIFilter-namn (samma
/// filter Bilder-appens eget filterval använder), inga uppgissade/
/// odokumenterade filter.
public struct PhotoFilterService {
    public struct FilterError: LocalizedError {
        let message: String
        public var errorDescription: String? { message }
    }

    public init() {}

    public func apply(_ filter: PhotoFilter, to image: PlatformImage) throws -> PlatformImage {
        guard filter != .none else { return image }

        guard let cgImage = image.cgImageRepresentation else {
            throw FilterError(message: "Kunde inte läsa bilddata.")
        }

        let source = CIImage(cgImage: cgImage)
        let extent = source.extent
        let output: CIImage

        switch filter {
        case .none:
            return image

        case .blackAndWhite:
            output = try Self.runFilter("CIPhotoEffectNoir", image: source)

        case .sepia:
            guard let ciFilter = CIFilter(name: "CISepiaTone") else {
                throw FilterError(message: "Kunde inte skapa sepiafilter.")
            }
            ciFilter.setValue(source, forKey: kCIInputImageKey)
            ciFilter.setValue(0.85, forKey: kCIInputIntensityKey)
            guard let sepiaOutput = ciFilter.outputImage else {
                throw FilterError(message: "Kunde inte tillämpa sepia.")
            }
            output = sepiaOutput

        case .xray:
            // Gråskala + inverterade färger - klassisk röntgenbilds-känsla.
            let mono = try Self.runFilter("CIPhotoEffectMono", image: source)
            output = try Self.runFilter("CIColorInvert", image: mono)

        case .chrome:
            output = try Self.runFilter("CIPhotoEffectChrome", image: source)

        case .fade:
            output = try Self.runFilter("CIPhotoEffectFade", image: source)

        case .comic:
            output = try Self.runFilter("CIComicEffect", image: source)

        case .thermal:
            // Ingen inbyggd "termisk" CIFilter finns - byggs av gråskala
            // (CIColorControls, mättnad 0) följt av CIFalseColor, som
            // mappar mörkt/ljust mot en lila→gul gradient likt en
            // värmekamerabild.
            guard let grayscaleFilter = CIFilter(name: "CIColorControls") else {
                throw FilterError(message: "Kunde inte skapa värmekamerafiltret.")
            }
            grayscaleFilter.setValue(source, forKey: kCIInputImageKey)
            grayscaleFilter.setValue(0, forKey: kCIInputSaturationKey)
            guard let grayscale = grayscaleFilter.outputImage,
                  let falseColorFilter = CIFilter(name: "CIFalseColor") else {
                throw FilterError(message: "Kunde inte skapa värmekamerafiltret.")
            }
            falseColorFilter.setValue(grayscale, forKey: kCIInputImageKey)
            falseColorFilter.setValue(CIColor(red: 0.05, green: 0.0, blue: 0.3), forKey: "inputColor0")
            falseColorFilter.setValue(CIColor(red: 1.0, green: 0.9, blue: 0.1), forKey: "inputColor1")
            guard let thermalOutput = falseColorFilter.outputImage else {
                throw FilterError(message: "Kunde inte tillämpa värmekameraeffekten.")
            }
            output = thermalOutput

        case .poster:
            guard let ciFilter = CIFilter(name: "CIColorPosterize") else {
                throw FilterError(message: "Kunde inte skapa posterfilter.")
            }
            ciFilter.setValue(source, forKey: kCIInputImageKey)
            ciFilter.setValue(6, forKey: "inputLevels")
            guard let posterOutput = ciFilter.outputImage else {
                throw FilterError(message: "Kunde inte tillämpa poster-effekten.")
            }
            output = posterOutput

        case .instant:
            output = try Self.runFilter("CIPhotoEffectInstant", image: source)
        }

        let context = CIContext()
        guard let outputCGImage = context.createCGImage(output, from: extent) else {
            throw FilterError(message: "Kunde inte rendera det filtrerade resultatet.")
        }
        return PlatformImage(cgImageRepresentation: outputCGImage)
    }

    private static func runFilter(_ name: String, image: CIImage) throws -> CIImage {
        guard let ciFilter = CIFilter(name: name) else {
            throw FilterError(message: "Kunde inte skapa filtret \(name).")
        }
        ciFilter.setValue(image, forKey: kCIInputImageKey)
        guard let output = ciFilter.outputImage else {
            throw FilterError(message: "Kunde inte tillämpa filtret.")
        }
        return output
    }
}
