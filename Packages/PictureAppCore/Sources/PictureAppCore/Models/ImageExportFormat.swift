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
        switch self {
        case .png: return "PNG (med genomskinlighet)"
        case .jpeg: return "JPEG (mindre fil)"
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
