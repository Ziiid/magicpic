import AppKit
import UniformTypeIdentifiers
import PictureAppCore

/// Sparar via NSSavePanel, precis som tidigare - användaren väljer själv var
/// filen ska hamna.
@MainActor
struct MacImageExporter: ImageExporter {
    enum ExportError: LocalizedError {
        case noData
        var errorDescription: String? { "Kunde inte skapa bilddata." }
    }

    func export(image: PlatformImage, format: ImageExportFormat, suggestedName: String) async throws {
        guard let data = image.exportData(as: format) else { throw ExportError.noData }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = suggestedName

        let url: URL? = await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
        guard let url else { return }
        try data.write(to: url)
    }
}
