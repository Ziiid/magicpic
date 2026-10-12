import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Sparar/läser den PÅGÅENDE redigeringen på disk så den kan återupptas
/// efter att appen stängts ("Fortsätt där du slutade"). En enda session -
/// den senaste - i appens egen Application Support-mapp:
///
///   session.json   - alla redigeringsval (se `SavedSession`)
///   original.png   - originalbilden
///   mask.png       - den färdiga masken (8-bitars gråskala, inkl. penseln)
///   logo.png       - logotypen, om en finns
///   background.png - egen bakgrundsbild, om vald
///
/// En `actor` så att skrivningar aldrig överlappar, och så att de tunga
/// PNG-kodningarna hålls borta från huvudtråden. Bilderna kodas om BARA när
/// instansen faktiskt bytts (jämförs med `===`) - annars skrevs en hel
/// originalbild om vid varje liten ändring.
actor SessionStore {
    static let shared = SessionStore()

    // MARK: - Sparat format

    struct SavedSession: Codable {
        var title: String
        var exportFormat: String
        var background: SavedBackground
        var photoFilter: String
        var adjustments: [Double]
        var effects: [Double]?
        var outlineColor: [Double]?
        var shapeID: String
        var freeform: [[Double]]?
        var transform: SavedTransform
        var text: SavedText?
        var logo: SavedLogo?
        var selectedSubjectIDs: [Int]?
        var hasMask: Bool
        var savedAt: Date
    }

    struct SavedBackground: Codable {
        var kind: String // transparent | color | blurred | custom
        var color: [Double]? // r, g, b, a (sRGB)
        var gradientID: String?
        var transform: SavedTransform?
    }

    struct SavedTransform: Codable {
        var offsetX: Double
        var offsetY: Double
        var scale: Double
        var rotationDegrees: Double
        var isMirrored: Bool?
    }

    struct SavedText: Codable {
        var text: String
        var fontStyle: String
        var color: [Double]
        var size: Double
        var offsetX: Double
        var offsetY: Double
        var rotationDegrees: Double
        var hasShadow: Bool
    }

    struct SavedLogo: Codable {
        var size: Double
        var offsetX: Double
        var offsetY: Double
        var rotationDegrees: Double
        var isFlipped: Bool
        var isInFront: Bool
    }

    /// Det som returneras vid inläsning: den avkodade sessionen plus
    /// råbilderna.
    struct LoadedSession {
        var session: SavedSession
        var original: PlatformImage
        var mask: CVPixelBuffer?
        var logoImage: PlatformImage?
        var backgroundImage: PlatformImage?
    }

    /// Det som skickas IN vid sparning (bilder som instanser, så att
    /// aktören kan avgöra om de behöver kodas om).
    struct Input {
        var session: SavedSession
        var original: PlatformImage
        var mask: BackgroundRemovalService.ForegroundMask?
        var logoImage: PlatformImage?
        var backgroundImage: PlatformImage?
    }

    // MARK: - Katalog

    private var directory: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("XtraPic", isDirectory: true).appendingPathComponent("Session", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Senast skrivna instanser - se klassdokumentationen.
    private var lastOriginal: PlatformImage?
    private var lastLogo: PlatformImage?
    private var lastBackground: PlatformImage?
    private var lastMaskID: UUID?

    // MARK: - Finns en session?

    func hasSession() -> Bool {
        guard let dir = directory else { return false }
        let fm = FileManager.default
        return fm.fileExists(atPath: dir.appendingPathComponent("session.json").path)
            && fm.fileExists(atPath: dir.appendingPathComponent("original.png").path)
    }

    // MARK: - Skriv

    func write(_ input: Input) {
        guard let dir = directory else { return }

        if lastOriginal !== input.original || !FileManager.default.fileExists(atPath: dir.appendingPathComponent("original.png").path) {
            guard let data = input.original.pngData() else { return }
            guard (try? data.write(to: dir.appendingPathComponent("original.png"), options: .atomic)) != nil else { return }
            lastOriginal = input.original
        }

        let maskURL = dir.appendingPathComponent("mask.png")
        if let mask = input.mask {
            if lastMaskID != mask.id {
                if let data = Self.maskPNG(mask.mask), (try? data.write(to: maskURL, options: .atomic)) != nil {
                    lastMaskID = mask.id
                }
            }
        } else {
            try? FileManager.default.removeItem(at: maskURL)
            lastMaskID = nil
        }

        writeOptionalImage(input.logoImage, last: &lastLogo, name: "logo.png", in: dir)
        writeOptionalImage(input.backgroundImage, last: &lastBackground, name: "background.png", in: dir)

        var session = input.session
        session.hasMask = input.mask != nil
        guard let json = try? JSONEncoder().encode(session) else { return }
        // session.json skrivs SIST - finns den, finns alla bilder den pekar på.
        try? json.write(to: dir.appendingPathComponent("session.json"), options: .atomic)
    }

    private func writeOptionalImage(_ image: PlatformImage?, last: inout PlatformImage?, name: String, in dir: URL) {
        let url = dir.appendingPathComponent(name)
        guard let image else {
            try? FileManager.default.removeItem(at: url)
            last = nil
            return
        }
        if last !== image || !FileManager.default.fileExists(atPath: url.path) {
            if let data = image.pngData(), (try? data.write(to: url, options: .atomic)) != nil {
                last = image
            }
        }
    }

    // MARK: - Läs

    func load() -> LoadedSession? {
        guard let dir = directory,
              let json = try? Data(contentsOf: dir.appendingPathComponent("session.json")),
              let session = try? JSONDecoder().decode(SavedSession.self, from: json),
              let originalData = try? Data(contentsOf: dir.appendingPathComponent("original.png")),
              let original = PlatformImage.normalizedOrientation(from: originalData)
        else { return nil }

        func image(_ name: String) -> PlatformImage? {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
            return PlatformImage.normalizedOrientation(from: data)
        }

        var mask: CVPixelBuffer?
        if session.hasMask, let data = try? Data(contentsOf: dir.appendingPathComponent("mask.png")) {
            mask = Self.pixelBuffer(fromMaskPNG: data)
        }

        // De återlästa bilderna ÄR nu "senast skrivna" - skriv inte om dem
        // i onödan vid nästa autosparning (viewmodellen återanvänder samma
        // instanser).
        lastOriginal = original
        let logo = session.logo != nil ? image("logo.png") : nil
        let background = session.background.kind == "custom" ? image("background.png") : nil
        lastLogo = logo
        lastBackground = background

        return LoadedSession(session: session, original: original, mask: mask, logoImage: logo, backgroundImage: background)
    }

    // MARK: - Rensa

    func clear() {
        guard let dir = directory else { return }
        try? FileManager.default.removeItem(at: dir)
        lastOriginal = nil
        lastLogo = nil
        lastBackground = nil
        lastMaskID = nil
    }

    // MARK: - Mask <-> PNG

    private static func maskPNG(_ buffer: CVPixelBuffer) -> Data? {
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cg = CIContext().createCGImage(
            ci, from: ci.extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray()
        ) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private static func pixelBuffer(fromMaskPNG data: Data) -> CVPixelBuffer? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = cg.width
        let height = cg.height
        var maybeBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_OneComponent8,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &maybeBuffer
        )
        guard let buffer = maybeBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
              ) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}

// MARK: - Konvertering värdetyper <-> sparat format

extension SessionStore.SavedTransform {
    init(_ t: CanvasTransform) {
        self.init(
            offsetX: Double(t.offset.width), offsetY: Double(t.offset.height),
            scale: Double(t.scale), rotationDegrees: t.rotation.degrees,
            isMirrored: t.isMirrored
        )
    }

    var canvasTransform: CanvasTransform {
        CanvasTransform(
            offset: CGSize(width: offsetX, height: offsetY),
            scale: CGFloat(scale),
            rotation: .degrees(rotationDegrees),
            isMirrored: isMirrored ?? false
        )
    }
}

extension Color {
    /// r, g, b, a i sRGB - för att kunna sparas som JSON.
    var srgbComponents: [Double] {
        let cg = resolvedCGColor
        if let space = CGColorSpace(name: CGColorSpace.sRGB),
           let converted = cg.converted(to: space, intent: .defaultIntent, options: nil),
           let c = converted.components, c.count >= 3 {
            return [Double(c[0]), Double(c[1]), Double(c[2]), Double(converted.alpha)]
        }
        return [1, 1, 1, 1]
    }

    init(srgbComponents c: [Double]) {
        let v = c.count >= 4 ? c : [1, 1, 1, 1]
        self.init(.sRGB, red: v[0], green: v[1], blue: v[2], opacity: v[3])
    }
}
