import CoreGraphics
import CoreImage
import CoreVideo
import Foundation

/// En muterbar kopia av en Vision-genererad mask, så användaren kan måla
/// till eller bort delar för hand (t.ex. hårstrån eller skuggor Vision
/// missade). Målningen skriver direkt i pixelbufferten - billigt nog att
/// göra för varje penseldrag utan att det märks.
public final class EditableMask {
    private(set) var pixelBuffer: CVPixelBuffer
    public let width: Int
    public let height: Int

    private static let ciContext = CIContext()

    /// `source` muteras aldrig - den kan vara delad med cachad state i
    /// `SearchViewModel`. Kopian skapas ALLTID i ett känt, fixerat format
    /// (`kCVPixelFormatType_OneComponent8`, 8-bitars gråskala) via
    /// `CIContext.render`, istället för att - som tidigare - anta att
    /// `source` redan råkade ha exakt det formatet och memcpy:a de råa
    /// bytesen rakt av. Visions dokumenterade format för den här sortens
    /// mask gick inte att verifiera med säkerhet (se `buggs.md`), och en
    /// felaktig gissning gjorde att `paint(at:radius:adding:)`s
    /// `CGContext`, som hårdkodar `bitsPerComponent: 8`/`DeviceGray`,
    /// antingen misslyckades tyst eller ritade i data som tolkades fel -
    /// vilket visade sig som att penseln träffade fel plats och att
    /// "lägg till"/"ta bort" gav samma (trasiga) resultat (rapporterat
    /// 2026-09-25). `CIContext.render` konverterar automatiskt FRÅN
    /// källans faktiska format oavsett vilket det är, så `pixelBuffer`
    /// garanterat matchar vad `paint` förväntar sig.
    public init(copying source: CVPixelBuffer) {
        width = CVPixelBufferGetWidth(source)
        height = CVPixelBufferGetHeight(source)

        var maybeCopy: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_OneComponent8,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &maybeCopy
        )

        guard let copy = maybeCopy else {
            // Osannolikt (bara vid extremt minnestryck), men hellre måla i
            // en delad buffert än att krascha.
            pixelBuffer = source
            return
        }

        Self.ciContext.render(
            CIImage(cvPixelBuffer: source),
            to: copy,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: CGColorSpaceCreateDeviceGray()
        )
        pixelBuffer = copy
    }

    /// Målar en fylld cirkel i maskbufferten. `point` är i maskens EGNA
    /// pixelkoordinater (0,0 uppe till vänster, som en bild). `adding` = lägg
    /// till motivet (vitt, behålls vid kompositering), annars ta bort
    /// (svart, blir bakgrund).
    public func paint(at point: CGPoint, radius: CGFloat, adding: Bool) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let context = CGContext(
            data: base,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return }

        // CGContext ritar med (0,0) längst ner, men `point` ges i vanliga
        // bild-pixelkoordinater (0,0 uppe till vänster) - flippa Y.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        context.setFillColor(gray: adding ? 1.0 : 0.0, alpha: 1.0)
        context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
    }
}
