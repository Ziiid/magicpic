import SwiftUI

/// Bakgrundsvalet som visas i UI. Skiljs från `BackgroundRemovalService.BackgroundStyle`
/// eftersom det behöver bära en SwiftUI-`Color` (för `ColorPicker`-bindningen)
/// istället för en redan upplöst `CGColor`.
public enum BackgroundOption: Equatable {
    case transparent
    case color(Color)
    case blurredOriginal
    case gradient(GradientPreset)
    case custom(PlatformImage, transform: CanvasTransform = .identity)

    public static func == (lhs: BackgroundOption, rhs: BackgroundOption) -> Bool {
        switch (lhs, rhs) {
        case (.transparent, .transparent), (.blurredOriginal, .blurredOriginal):
            return true
        case (.color(let l), .color(let r)):
            return l == r
        case (.gradient(let l), .gradient(let r)):
            return l == r
        case (.custom(let l, let lt), .custom(let r, let rt)):
            return l === r && lt == rt
        default:
            return false
        }
    }

    /// Förvalda bakgrundsfärger i `BackgroundStylePickerView`s rutnät med
    /// riktiga förhandsgranskningar.
    public static let presetColors: [Color] = [
        .white, .black, .gray, .red, .orange, .yellow,
        .green, .mint, .teal, .blue, .purple, .pink,
    ]

    var serviceStyle: BackgroundRemovalService.BackgroundStyle {
        switch self {
        case .transparent:
            return .transparent
        case .color(let color):
            return .color(color.resolvedCGColor)
        case .blurredOriginal:
            return .blurredOriginal()
        case .gradient(let preset):
            return .gradient(
                start: preset.startCGColor, end: preset.endCGColor,
                startPoint: preset.startUnitPoint, endPoint: preset.endUnitPoint
            )
        case .custom(let image, let transform):
            return .custom(image, transform: transform)
        }
    }
}
