import Foundation

/// Plattformarnas sätt att spara en bild skiljer sig helt (NSSavePanel på
/// macOS, Foton-biblioteket/dela-ark på iOS). Den delade koden känner bara
/// till detta protokoll; respektive apptarget tillhandahåller en konkret
/// implementation.
@MainActor
public protocol ImageExporter {
    /// Returnerar `true` om bilden faktiskt sparades, `false` om användaren
    /// avbröt (t.ex. stängde spara-panelen) - så appen bara bekräftar en
    /// riktig sparning.
    func export(image: PlatformImage, format: ImageExportFormat, suggestedName: String) async throws -> Bool
}
