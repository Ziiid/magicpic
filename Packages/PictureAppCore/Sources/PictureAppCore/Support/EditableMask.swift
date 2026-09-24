import CoreGraphics
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

    /// `source` muteras aldrig - den kan vara delad med cachad state i
    /// `SearchViewModel`.
    public init(copying source: CVPixelBuffer) {
        width = CVPixelBufferGetWidth(source)
        height = CVPixelBufferGetHeight(source)

        var maybeCopy: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            CVPixelBufferGetPixelFormatType(source),
            nil, &maybeCopy
        )

        guard let copy = maybeCopy else {
            // Osannolikt (bara vid extremt minnestryck), men hellre måla i
            // en delad buffert än att krascha.
            pixelBuffer = source
            return
        }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(copy, [])
        }
        if let sourceBase = CVPixelBufferGetBaseAddress(source),
           let destBase = CVPixelBufferGetBaseAddress(copy) {
            let sourceStride = CVPixelBufferGetBytesPerRow(source)
            let destStride = CVPixelBufferGetBytesPerRow(copy)
            let rowBytes = min(sourceStride, destStride)
            for row in 0..<height {
                memcpy(destBase + row * destStride, sourceBase + row * sourceStride, rowBytes)
            }
        }
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
