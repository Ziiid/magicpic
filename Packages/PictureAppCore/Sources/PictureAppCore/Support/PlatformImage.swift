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
