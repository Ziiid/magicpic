import AppKit
import UniformTypeIdentifiers
import PictureAppCore

/// Sparar via NSSavePanel, precis som tidigare - användaren väljer själv var
/// filen ska hamna.
@MainActor
struct MacImageExporter: ImageExporter {
    enum ExportError: LocalizedError {
        case noData
        var errorDescription: String? { "Kunde inte skapa PNG-data." }
    }

    func export(image: PlatformImage, suggestedName: String) async throws {
        guard let data = image.pngData() else { throw ExportError.noData }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
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
