import SwiftUI

/// Bakgrundsvalet som visas i UI. Skiljs från `BackgroundRemovalService.BackgroundStyle`
/// eftersom det behöver bära en SwiftUI-`Color` (för `ColorPicker`-bindningen)
/// istället för en redan upplöst `CGColor`.
public enum BackgroundOption: Equatable {
    case transparent
    case color(Color)
    case blurredOriginal
    case custom(PlatformImage, transform: CanvasTransform = .identity)

    public static func == (lhs: BackgroundOption, rhs: BackgroundOption) -> Bool {
        switch (lhs, rhs) {
        case (.transparent, .transparent), (.blurredOriginal, .blurredOriginal):
            return true
        case (.color(let l), .color(let r)):
            return l == r
        case (.custom(let l, let lt), .custom(let r, let rt)):
            return l === r && lt == rt
        default:
            return false
        }
    }

    /// Förvalda bakgrundsfärger - delad mellan `BackgroundStylePickerView`s
    /// rutnät med riktiga förhandsgranskningar och den enkla färgcirkel-
    /// rutan i DetailPanels "Fler färger…"-sheet, så de alltid visar samma
    /// urval.
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
        case .custom(let image, let transform):
            return .custom(image, transform: transform)
        }
    }
}
