import CoreGraphics
import Foundation

/// Storlek (längsta sidan) att spara/dela i. Bilden förminskas bara, aldrig
/// förstoras. "Original" = bildens egen upplösning (eller en genvägs fasta
/// pixelmått, t.ex. "Instagram-inlägg").
public enum ExportSize: String, CaseIterable, Identifiable {
    case original
    case large
    case medium
    case small

    public var id: String { rawValue }

    /// `nil` = ingen förminskning.
    public var maxDimension: CGFloat? {
        switch self {
        case .original: return nil
        case .large: return 2048
        case .medium: return 1080
        case .small: return 512
        }
    }

    public var label: String {
        let locale = AppLanguage.current.locale
        switch self {
        case .original: return String(localized: "Originalstorlek", bundle: .module, locale: locale)
        case .large: return String(localized: "Stor (2048 px)", bundle: .module, locale: locale)
        case .medium: return String(localized: "Medel (1080 px)", bundle: .module, locale: locale)
        case .small: return String(localized: "Liten (512 px)", bundle: .module, locale: locale)
        }
    }
}
