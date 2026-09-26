import Photos
import PictureAppCore

/// Sparar till Foton-biblioteket, motsvarigheten till Mac-versionens
/// "Spara var du vill"-panel eftersom iOS-appar saknar filsystemsåtkomst
/// utanför sin egen sandlåda.
@MainActor
struct IOSImageExporter: ImageExporter {
    enum ExportError: LocalizedError {
        case noData
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .noData: return "Kunde inte skapa bilddata."
            case .permissionDenied: return "PictureApp saknar behörighet att spara i Foton."
            }
        }
    }

    /// `format` avgör bara "Dela"-flödets fil (se `SearchViewModel.
    /// refreshShareURL()`) och Mac-sparflödet - Foton-biblioteket sparas
    /// alltid i sitt naturliga format via `creationRequestForAsset` (bevarar
    /// redan genomskinlighet för källor med alfakanal). Att själv styra
    /// exakt JPEG/PNG-kodning för Foton-sparningen kräver en lägre nivås
    /// API (`PHAssetCreationRequest.addResource`) - inte värt
    /// riskökningen för den marginella nyttan här.
    func export(image: PlatformImage, format: ImageExportFormat, suggestedName: String) async throws {
        guard image.exportData(as: format) != nil else { throw ExportError.noData }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.permissionDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}
