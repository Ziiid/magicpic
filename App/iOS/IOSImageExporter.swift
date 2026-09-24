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
            case .noData: return "Kunde inte skapa PNG-data."
            case .permissionDenied: return "PictureApp saknar behörighet att spara i Foton."
            }
        }
    }

    func export(image: PlatformImage, suggestedName: String) async throws {
        guard image.pngData() != nil else { throw ExportError.noData }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.permissionDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }
    }
}
