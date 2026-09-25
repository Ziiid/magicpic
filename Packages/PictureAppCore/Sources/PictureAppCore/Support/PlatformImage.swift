import CoreImage
import ImageIO
import SwiftUI

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif

/// Bryggar plattformarnas bildtyper (NSImage / UIImage) så att delad kod
/// (Vision-bearbetning, SwiftUI-vyer) kan skrivas en gång för båda målen.
public extension PlatformImage {
    var cgImageRepresentation: CGImage? {
        #if os(macOS)
        return cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        return cgImage
        #endif
    }

    convenience init(cgImageRepresentation cgImage: CGImage) {
        #if os(macOS)
        self.init(cgImage: cgImage, size: .zero)
        #else
        self.init(cgImage: cgImage)
        #endif
    }

    /// Läser in `data` och bakar in en ev. EXIF-rotation i själva pixel-
    /// datan istället för att lämna den som separat metadata. `cgImage`/
    /// `cgImage(forProposedRect:...)` ovan returnerar bildens RÅA
    /// sensor-orientering utan hänsyn till EXIF-taggen - `UIImage`/`NSImage`
    /// själva visar bilden rätt (de respekterar taggen vid ritning), men
    /// hela Vision-/CoreImage-pipelinen (`BackgroundRemovalService`,
    /// `ShapeCropService`) går via `cgImageRepresentation`, som tappar
    /// rotationen. En stående bild kunde därför plötsligt hamna liggande
    /// så fort den bearbetats en gång (upptäckt 2026-09-25 - märktes först
    /// när panorering av motivet började trigga bearbetning direkt).
    /// Normaliserar därför en gång, vid inläsning, med ImageIO/CoreImage
    /// (plattformsoberoende, ingen AppKit/UIKit-särskillnad behövs).
    static func normalizedOrientation(from data: Data) -> PlatformImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return PlatformImage(data: data)
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = (properties?[kCGImagePropertyOrientation] as? UInt32) ?? CGImagePropertyOrientation.up.rawValue
        guard let orientation = CGImagePropertyOrientation(rawValue: rawOrientation), orientation != .up else {
            return PlatformImage(cgImageRepresentation: cgImage)
        }

        let oriented = CIImage(cgImage: cgImage).oriented(orientation)
        guard let normalized = CIContext().createCGImage(oriented, from: oriented.extent) else {
            return PlatformImage(cgImageRepresentation: cgImage)
        }
        return PlatformImage(cgImageRepresentation: normalized)
    }

    /// Samma normalisering som `normalizedOrientation(from:)`, men för en
    /// redan avkodad `PlatformImage` utan tillgång till originaldatan (t.ex.
    /// en bild som släpptes in direkt som objekt, inte via en fil-URL - se
    /// `ContentView.handleDrop`). `pngData()` kodar via bildens egen,
    /// orienteringskorrekta ritväg (till skillnad från `cgImageRepresentation`),
    /// så PNG-datan är redan rättvänd när den går igenom
    /// `normalizedOrientation(from:)` igen.
    func normalizedOrientation() -> PlatformImage {
        guard let data = pngData(), let normalized = Self.normalizedOrientation(from: data) else {
            return self
        }
        return normalized
    }

    /// Skalar ner bilden så längsta sidan är högst `maxDimension` punkter -
    /// för snabba förhandsvisningsminiatyrer (t.ex. filterväljaren) utan
    /// att köra tunga CoreImage-filter på en bild i full upplösning.
    func resized(maxDimension: CGFloat) -> PlatformImage {
        guard let cgImage = cgImageRepresentation else { return self }
        let ciImage = CIImage(cgImage: cgImage)
        let scale = maxDimension / max(ciImage.extent.width, ciImage.extent.height)
        guard scale < 1 else { return self }

        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let output = CIContext().createCGImage(scaled, from: scaled.extent) else { return self }
        return PlatformImage(cgImageRepresentation: output)
    }
}

#if os(macOS)
public extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}
#endif

public extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}
