import Foundation

/// Bildkorrigeringar som tillämpas på originalbilden INNAN Vision-analysen/
/// bakgrundsborttagningen körs - de blir en del av fotot självt, precis som
/// att redigera bilden före beskärning (se `ImageAdjustmentService`).
///
/// De flesta värden är symmetriska (-1...1, 0 = oförändrad); de som bara
/// kan gå åt ett håll med de underliggande CoreImage-filtren (skärpa,
/// highlights, shadows, brusreducering, vinjett) är istället 0...1, där
/// 0 = oförändrad.
public struct ImageAdjustments: Equatable {
    /// -1...1, 0 = oförändrad. `CIColorControls` brightness.
    public var brightness: Double
    /// -1...1, 0 = oförändrad (kontrast faktor ×1). `CIColorControls` contrast.
    public var contrast: Double
    /// -1...1, 0 = oförändrad (mättnad faktor ×1). `CIColorControls` saturation.
    public var saturation: Double
    /// -1...1, negativt = kallare/blåare, positivt = varmare/orangeare.
    /// `CITemperatureAndTint`.
    public var temperature: Double
    /// 0...1, 0 = oförändrad. Återställer urblekta högdagrar.
    /// `CIHighlightShadowAdjust`.
    public var highlights: Double
    /// 0...1, 0 = oförändrad. Lyfter mörka skuggpartier.
    /// `CIHighlightShadowAdjust`.
    public var shadows: Double
    /// 0...1, 0 = ingen skärpning. `CISharpenLuminance`.
    public var sharpness: Double
    /// 0...1, 0 = ingen brusreducering. `CINoiseReduction`.
    public var noiseReduction: Double
    /// 0...1, 0 = ingen vinjett. `CIVignette`.
    public var vignette: Double

    public static let identity = ImageAdjustments()

    public init(
        brightness: Double = 0,
        contrast: Double = 0,
        saturation: Double = 0,
        temperature: Double = 0,
        highlights: Double = 0,
        shadows: Double = 0,
        sharpness: Double = 0,
        noiseReduction: Double = 0,
        vignette: Double = 0
    ) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.temperature = temperature
        self.highlights = highlights
        self.shadows = shadows
        self.sharpness = sharpness
        self.noiseReduction = noiseReduction
        self.vignette = vignette
    }

    public var isIdentity: Bool { self == .identity }
}
