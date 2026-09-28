import Foundation
import UniformTypeIdentifiers

/// Filformat att spara/dela slutresultatet i - se `PlatformImage.exportData(as:)`
/// för själva kodningen och `SearchViewModel.exportFormat` för var valet
/// hålls. JPEG saknar stöd för genomskinlighet (en genomskinlig bakgrund
/// läggs mot vit innan kodningen).
public enum ImageExportFormat: String, CaseIterable, Identifiable {
    case png
    case jpeg

    public var id: String { rawValue }

    public var label: String {
        let locale = AppLanguage.current.locale
        switch self {
        case .png: return String(localized: "PNG (med genomskinlighet)", bundle: .module, locale: locale)
        case .jpeg: return String(localized: "JPEG (mindre fil)", bundle: .module, locale: locale)
        }
    }

    public var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }

    public var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }
}
