import Foundation

/// Plattformarnas sätt att spara en bild skiljer sig helt (NSSavePanel på
/// macOS, Foton-biblioteket/dela-ark på iOS). Den delade koden känner bara
/// till detta protokoll; respektive apptarget tillhandahåller en konkret
/// implementation.
@MainActor
public protocol ImageExporter {
    func export(image: PlatformImage, suggestedName: String) async throws
}
