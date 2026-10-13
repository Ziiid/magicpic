import CoreGraphics
import CoreImage
import Foundation

/// Lägger skugga och/eller kontur på ett genomskinligt motivurklipp.
/// Bara CoreImage-filter som finns i Apples egen uppsättning
/// (`CIMorphologyMaximum`, `CISourceInCompositing`, `CIGaussianBlur`,
/// `CIColorMatrix`, `CISourceOverCompositing`).
public struct SubjectEffectService {
    public struct EffectError: LocalizedError {
        let message: String
        public var errorDescription: String? {
            String(localized: String.LocalizationValue(message), bundle: .module, locale: AppLanguage.current.locale)
        }
    }

    public init() {}

    public func apply(_ effects: SubjectEffects, to image: PlatformImage) throws -> PlatformImage {
        guard !effects.isNone else { return image }
        guard let cgImage = image.cgImageRepresentation else {
            throw EffectError(message: "Kunde inte läsa bilddata.")
        }

        let subject = CIImage(cgImage: cgImage)
        let extent = subject.extent
        let longest = max(extent.width, extent.height)

        // Den form skuggan kastas av: motivet INKLUSIVE ev. kontur.
        var silhouette = subject
        var layers: [CIImage] = [subject]

        if effects.outlineWidth > 0 {
            // Utvidga motivets alfa utåt (dilatering) och färga ytan.
            let radius = min(max(effects.outlineWidth * longest * 0.02, 1), 48)
            guard let dilateFilter = CIFilter(name: "CIMorphologyMaximum") else {
                throw EffectError(message: "Kunde inte skapa bildfilter.")
            }
            dilateFilter.setValue(subject, forKey: kCIInputImageKey)
            dilateFilter.setValue(radius, forKey: kCIInputRadiusKey)
            guard let dilated = dilateFilter.outputImage else {
                throw EffectError(message: "Kunde inte skapa konturen.")
            }
            let color = CIImage(color: CIColor(cgColor: effects.outlineColor.resolvedCGColor)).cropped(to: dilated.extent)
            let outline = color.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: dilated])
            layers.append(outline)
            silhouette = outline.composited(over: subject)
        }

        if effects.shadow > 0 {
            // Svart skugga från silhuetten, suddad och förskjuten nedåt.
            let blurRadius = max(effects.shadow * longest * 0.02, 1)
            let opacity = 0.25 + 0.5 * effects.shadow
            let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 1)).cropped(to: silhouette.extent)
            let flat = black.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: silhouette])
            guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
                throw EffectError(message: "Kunde inte skapa bildfilter.")
            }
            blurFilter.setValue(flat, forKey: kCIInputImageKey)
            blurFilter.setValue(blurRadius, forKey: kCIInputRadiusKey)
            guard let blurred = blurFilter.outputImage else {
                throw EffectError(message: "Kunde inte skapa skuggan.")
            }
            let faded = blurred.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)),
            ])
            // CoreImages y-axel pekar uppåt - negativt Y = nedåt på skärmen.
            let shadow = faded.transformed(by: CGAffineTransform(translationX: 0, y: -effects.shadow * longest * 0.015 - 1))
            layers.append(shadow)
        }

        // layers: [motiv, kontur?, skugga?] - rita bakifrån (skugga längst
        // bak, motivet överst).
        var result = CIImage(color: .clear).cropped(to: extent)
        for layer in layers.reversed() {
            result = layer.composited(over: result)
        }

        let context = SharedCIContext.shared
        guard let output = context.createCGImage(result, from: extent) else {
            throw EffectError(message: "Kunde inte rendera resultatet.")
        }
        return PlatformImage(cgImageRepresentation: output)
    }
}
