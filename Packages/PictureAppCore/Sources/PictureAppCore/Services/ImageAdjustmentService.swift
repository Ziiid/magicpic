import CoreImage

/// Tillämpar `ImageAdjustments` (ljusstyrka/kontrast/mättnad/temperatur/
/// highlights/shadows/skärpa/brusreducering/vinjett) på en bild, ren
/// CoreImage - körs på originalbilden INNAN Vision-analysen/
/// bakgrundsborttagningen (se `SearchViewModel.removeBackground()`), så
/// justeringarna blir en del av fotot självt. Billig nog att köras om vid
/// varje reglageändring; Vision-masken cachas separat mot den OJUSTERADE
/// originalbilden och behöver aldrig räknas om bara för att en justering
/// ändras.
public struct ImageAdjustmentService {
    public struct AdjustmentError: LocalizedError {
        let message: String
        public var errorDescription: String? { message }
    }

    public init() {}

    public func apply(_ adjustments: ImageAdjustments, to image: PlatformImage) throws -> PlatformImage {
        guard !adjustments.isIdentity else { return image }

        guard let cgImage = image.cgImageRepresentation else {
            throw AdjustmentError(message: "Kunde inte läsa bilddata.")
        }

        var current = CIImage(cgImage: cgImage)
        let extent = current.extent

        if adjustments.brightness != 0 || adjustments.contrast != 0 || adjustments.saturation != 0 {
            guard let filter = CIFilter(name: "CIColorControls") else {
                throw AdjustmentError(message: "Kunde inte skapa färgfilter.")
            }
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(adjustments.brightness, forKey: kCIInputBrightnessKey)
            filter.setValue(1 + adjustments.contrast, forKey: kCIInputContrastKey)
            filter.setValue(1 + adjustments.saturation, forKey: kCIInputSaturationKey)
            guard let output = filter.outputImage else {
                throw AdjustmentError(message: "Kunde inte justera ljusstyrka/kontrast/mättnad.")
            }
            current = output
        }

        if adjustments.highlights != 0 || adjustments.shadows != 0 {
            guard let filter = CIFilter(name: "CIHighlightShadowAdjust") else {
                throw AdjustmentError(message: "Kunde inte skapa highlights/shadows-filter.")
            }
            filter.setValue(current, forKey: kCIInputImageKey)
            // Native intervall: highlightAmount 1 = oförändrat (lägre
            // återställer urblekta högdagrar), shadowAmount 0 = oförändrat
            // (högre lyfter skuggor) - motsatt riktning mot varandra,
            // därav "1 -" bara på highlights.
            filter.setValue(1 - adjustments.highlights, forKey: "inputHighlightAmount")
            filter.setValue(adjustments.shadows, forKey: "inputShadowAmount")
            guard let output = filter.outputImage else {
                throw AdjustmentError(message: "Kunde inte justera highlights/shadows.")
            }
            current = output
        }

        if adjustments.temperature != 0 {
            guard let filter = CIFilter(name: "CITemperatureAndTint") else {
                throw AdjustmentError(message: "Kunde inte skapa temperaturfilter.")
            }
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
            filter.setValue(CIVector(x: 6500 - adjustments.temperature * 3000, y: 0), forKey: "inputTargetNeutral")
            guard let output = filter.outputImage else {
                throw AdjustmentError(message: "Kunde inte justera temperaturen.")
            }
            current = output
        }

        if adjustments.sharpness > 0 {
            guard let filter = CIFilter(name: "CISharpenLuminance") else {
                throw AdjustmentError(message: "Kunde inte skapa skärpefilter.")
            }
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(adjustments.sharpness * 2, forKey: kCIInputSharpnessKey)
            guard let output = filter.outputImage else {
                throw AdjustmentError(message: "Kunde inte skärpa bilden.")
            }
            current = output
        }

        if adjustments.noiseReduction > 0 {
            guard let filter = CIFilter(name: "CINoiseReduction") else {
                throw AdjustmentError(message: "Kunde inte skapa brusreduceringsfilter.")
            }
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(adjustments.noiseReduction * 0.1, forKey: "inputNoiseLevel")
            filter.setValue(0.4, forKey: "inputSharpness")
            guard let output = filter.outputImage else {
                throw AdjustmentError(message: "Kunde inte brusreducera bilden.")
            }
            current = output
        }

        if adjustments.vignette > 0 {
            guard let filter = CIFilter(name: "CIVignette") else {
                throw AdjustmentError(message: "Kunde inte skapa vinjettfilter.")
            }
            filter.setValue(current, forKey: kCIInputImageKey)
            filter.setValue(adjustments.vignette * 2, forKey: kCIInputIntensityKey)
            filter.setValue(min(extent.width, extent.height) * 0.75, forKey: kCIInputRadiusKey)
            guard let output = filter.outputImage else {
                throw AdjustmentError(message: "Kunde inte lägga till vinjett.")
            }
            current = output
        }

        let context = CIContext()
        guard let outputCGImage = context.createCGImage(current, from: extent) else {
            throw AdjustmentError(message: "Kunde inte rendera den justerade bilden.")
        }
        return PlatformImage(cgImageRepresentation: outputCGImage)
    }
}
