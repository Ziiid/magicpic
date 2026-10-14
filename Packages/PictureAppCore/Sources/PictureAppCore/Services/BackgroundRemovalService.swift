import Vision
import CoreImage
import Foundation

/// Klipper ut motivet helt på enheten med Apples Vision-ramverk
/// (VNGenerateForegroundInstanceMaskRequest) och kompositerar det mot valfri
/// bakgrund. Kräver ingen nätverksuppkoppling eller extern tjänst och är i
/// regel klart på under en sekund. Fungerar identiskt på macOS och iOS.
///
/// Masken (den dyra Vision-analysen) och kompositeringen (billig,
/// CoreImage-filter) är medvetet separata metoder: att byta bakgrundsstil
/// upprepade gånger på samma bild ska inte behöva köra Vision-analysen på
/// nytt varje gång.
public struct BackgroundRemovalService {
    public struct RemovalError: LocalizedError {
        let message: String
        // `String.LocalizationValue(_ value: String)` - en RUNTIME-nyckel
        // (inte en bokstavlig sträng vid kompileringstillfället) - gör att
        // ALLA `RemovalError(message: "...")`-anrop i den här filen kan
        // lokaliseras genom EN enda punkt istället för att skriva om varje
        // enskilt `throw`-ställe för sig.
        public var errorDescription: String? {
            L(String.LocalizationValue(message))
        }
    }

    /// Resultatet av Vision-analysen för en bild: originalet plus masken för
    /// motivet. Kan återanvändas för att kompositera mot flera olika
    /// bakgrunder utan att analysera bilden på nytt.
    ///
    /// `id` finns bara för att kunna jämföra två `ForegroundMask` för
    /// likhet (använt av `SearchViewModel`s undo/redo-historik för att
    /// avgöra om något faktiskt ändrats) - `CGImage`/`CVPixelBuffer` har
    /// ingen egen värdelikhet att jämföra med.
    public struct ForegroundMask: Equatable {
        public let id = UUID()
        let original: CGImage
        let mask: CVPixelBuffer

        public init(original: CGImage, mask: CVPixelBuffer) {
            self.original = original
            self.mask = mask
        }

        public static func == (lhs: ForegroundMask, rhs: ForegroundMask) -> Bool {
            lhs.id == rhs.id
        }
    }

    /// Ett enskilt motiv Vision hittat i bilden (av flera) - t.ex. en av två
    /// personer, eller en hund bredvid en person. `id` är Visions eget
    /// instansindex (används för att be Vision om en kombinerad mask för de
    /// instanser användaren valt). `mask` är motivets EGEN mask (bara den
    /// instansen), för att kunna rita en exakt konturerad markering i
    /// motivväljaren istället för bara en rektangel. `boundingBox` är en
    /// normaliserad ram (0...1, origo uppe till vänster - samma konvention
    /// som SwiftUI) runt motivet, för att placera väljarens tryckbara markör.
    public struct SubjectInstance: Identifiable {
        public let id: Int
        public let boundingBox: CGRect
        public let mask: CVPixelBuffer
    }

    /// Resultatet av att analysera en bild med Vision INNAN motivval gjorts:
    /// alla separata motiv Vision kunde urskilja. Håller kvar Visions egen
    /// `handler`/`observation` så att `combinedMask(selecting:from:)` kan
    /// bes om en NY kombinerad mask för ett annat urval senare, utan att
    /// köra om själva Vision-analysen (den dyra delen).
    public struct DetectedSubjects {
        public let original: CGImage
        public let instances: [SubjectInstance]
        let observation: VNInstanceMaskObservation
        let handler: VNImageRequestHandler
    }

    /// Vad urklippet ska läggas mot.
    public enum BackgroundStyle {
        case transparent
        case color(CGColor)
        case blurredOriginal(radius: Double = 30)
        /// Tvåfärgad lineär gradient; punkterna i enhetskoordinater (y nedåt).
        case gradient(start: CGColor, end: CGColor, startPoint: CGPoint, endPoint: CGPoint)
        case custom(PlatformImage, transform: CanvasTransform = .identity)
    }

    public init() {}

    /// Kör Vision-analysen och hittar ALLA separata motiv i bilden var för
    /// sig (inte bara en gemensam mask för alla på en gång, som tidigare) -
    /// det här är den dyra delen (typiskt under en sekund, men fortfarande
    /// värt att cacha om användaren bara byter bakgrund eller motivval).
    /// `combinedMask(selecting:from:)` används sedan för att slå ihop de
    /// instanser användaren faktiskt vill behålla till en färdig mask.
    public func detectSubjects(in image: PlatformImage) throws -> DetectedSubjects {
        guard let cgImage = image.cgImageRepresentation else {
            throw RemovalError(message: "Kunde inte läsa bilddata.")
        }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        guard let result = request.results?.first else {
            throw RemovalError(message: "Vision kunde inte analysera bilden.")
        }

        guard !result.allInstances.isEmpty else {
            throw RemovalError(message: "Hittade inget tydligt motiv att lyfta ur bakgrunden.")
        }

        // En mask per enskild instans - dyrare totalt sett än att bara be om
        // EN gemensam mask för alla instanser (tidigare beteende), men bara
        // marginellt (samma underliggande analys återanvänds via `handler`)
        // och krävs för att kunna visa/välja motiven var för sig.
        let instances = try result.allInstances.sorted().map { index -> SubjectInstance in
            let instanceMask = try result.generateScaledMaskForImage(forInstances: IndexSet(integer: index), from: handler)
            return SubjectInstance(id: index, boundingBox: Self.normalizedBoundingBox(of: instanceMask), mask: instanceMask)
        }

        return DetectedSubjects(original: cgImage, instances: instances, observation: result, handler: handler)
    }

    /// Slår ihop de VALDA instansernas masker till en enda, redo för
    /// `composite`. Om `selected` är tomt (t.ex. användaren råkade avmarkera
    /// allt) faller den tillbaka på ALLA instanser istället för att ge en
    /// helt tom (allt bakgrund) bild.
    public func combinedMask(selecting selected: Set<Int>, from subjects: DetectedSubjects) throws -> ForegroundMask {
        let indices = selected.isEmpty ? Set(subjects.instances.map(\.id)) : selected
        let maskPixelBuffer = try subjects.observation.generateScaledMaskForImage(
            forInstances: IndexSet(indices),
            from: subjects.handler
        )
        return ForegroundMask(original: subjects.original, mask: maskPixelBuffer)
    }

    /// Renderar en enskild instans mask som en färgad, halvgenomskinlig bild
    /// i bildens fulla storlek (färg där motivet är, genomskinligt annars) -
    /// för att kunna rita en markering i motivväljaren som följer motivets
    /// FAKTISKA form, inte bara en rektangel runt det.
    public func colorizedOverlay(for mask: CVPixelBuffer, color: CGColor, extent: CGRect) throws -> CGImage {
        guard let colorFilter = CIFilter(name: "CIConstantColorGenerator") else {
            throw RemovalError(message: "Kunde inte skapa färgfilter.")
        }
        colorFilter.setValue(CIColor(cgColor: color), forKey: kCIInputColorKey)
        guard let colorImage = colorFilter.outputImage?.cropped(to: extent) else {
            throw RemovalError(message: "Kunde inte skapa färgfilter.")
        }

        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            throw RemovalError(message: "Kunde inte skapa bildfilter.")
        }
        blendFilter.setValue(colorImage, forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage(color: .clear).cropped(to: extent), forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(CIImage(cvPixelBuffer: mask), forKey: kCIInputMaskImageKey)

        guard let outputImage = blendFilter.outputImage,
              let cgImage = SharedCIContext.shared.createCGImage(outputImage, from: extent) else {
            throw RemovalError(message: "Kunde inte rendera markeringen.")
        }
        return cgImage
    }

    /// Räknar ut en ungefärlig, normaliserad ram (0...1, origo uppe till
    /// vänster - samma konvention som SwiftUI) runt en enskild instans mask,
    /// för att placera motivväljarens tryckbara markör. Vision ger ingen
    /// egen bounding box per instans, så den skattas genom att skala ner
    /// masken till en liten provyta och läsa av var pixelvärdet är över ett
    /// tröskelvärde - vi behöver bara en ungefärlig ram för att placera en
    /// markör, inte pixelexakt precision, så nedskalningen håller kostnaden
    /// försumbar även för stora bilder.
    ///
    /// Renderar med SAMMA mönster (`CIContext.render(_:to:bounds:colorSpace:)`
    /// mot en `kCVPixelFormatType_OneComponent8`-buffert) som
    /// `EditableMask.init(copying:)` redan använder beprövat korrekt för
    /// Vision-masker i det här projektet (rad 0 = bildens överkant, som en
    /// vanlig bild) - se `buggs.md` om varför det INTE går att anta ett
    /// pixelformat/koordinatsystem utan att verifiera det.
    private static func normalizedBoundingBox(of mask: CVPixelBuffer) -> CGRect {
        let fallback = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        let maskImage = CIImage(cvPixelBuffer: mask)
        let extent = maskImage.extent
        guard extent.width > 0, extent.height > 0 else { return fallback }

        let sampleWidth = 80
        let sampleHeight = max(1, Int((extent.height / extent.width) * CGFloat(sampleWidth)))
        let scaled = maskImage.transformed(by: CGAffineTransform(
            scaleX: CGFloat(sampleWidth) / extent.width,
            y: CGFloat(sampleHeight) / extent.height
        ))

        var maybeSample: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, sampleWidth, sampleHeight, kCVPixelFormatType_OneComponent8, nil, &maybeSample)
        guard let sample = maybeSample else { return fallback }

        SharedCIContext.shared.render(
            scaled,
            to: sample,
            bounds: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight),
            colorSpace: CGColorSpaceCreateDeviceGray()
        )

        CVPixelBufferLockBaseAddress(sample, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(sample, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(sample) else { return fallback }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(sample)
        let pixels = base.assumingMemoryBound(to: UInt8.self)

        var minX = sampleWidth, minY = sampleHeight, maxX = -1, maxY = -1
        let threshold: UInt8 = 32
        for y in 0..<sampleHeight {
            for x in 0..<sampleWidth where pixels[y * bytesPerRow + x] > threshold {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return fallback }

        return CGRect(
            x: CGFloat(minX) / CGFloat(sampleWidth),
            y: CGFloat(minY) / CGFloat(sampleHeight),
            width: CGFloat(maxX - minX + 1) / CGFloat(sampleWidth),
            height: CGFloat(maxY - minY + 1) / CGFloat(sampleHeight)
        )
    }

    /// Lägger motivet från en redan beräknad mask mot vald bakgrund. Billig
    /// nog att köras varje gång användaren byter bakgrundsstil.
    ///
    /// - Parameter foregroundImage: Motivets pixeldata att kompositera -
    ///   default `foreground.original` (bilden masken beräknades från).
    ///   Skickas in separat när bildkorrigeringar (`ImageAdjustments`) ska
    ///   synas i resultatet: masken (dyr, Vision) cachas mot den OJUSTERADE
    ///   bilden, men själva urklippet ska ändå visa den JUSTERADE - masken
    ///   är fortfarande giltig eftersom justeringar inte ändrar motivets
    ///   geometri/kontur, bara dess färger.
    public func composite(_ foreground: ForegroundMask, background: BackgroundStyle, foregroundImage: CGImage? = nil) throws -> PlatformImage {
        let originalCI = CIImage(cgImage: foregroundImage ?? foreground.original)
        let maskCI = CIImage(cvPixelBuffer: foreground.mask)
        let backgroundCI = try makeBackgroundImage(background, original: originalCI, extent: originalCI.extent)

        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            throw RemovalError(message: "Kunde inte skapa bildfilter.")
        }
        blendFilter.setValue(originalCI, forKey: kCIInputImageKey)
        blendFilter.setValue(backgroundCI, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(maskCI, forKey: kCIInputMaskImageKey)

        guard let outputCIImage = blendFilter.outputImage else {
            throw RemovalError(message: "Kunde inte skapa resultatbilden.")
        }

        let context = SharedCIContext.shared
        guard let outputCGImage = context.createCGImage(outputCIImage, from: originalCI.extent) else {
            throw RemovalError(message: "Kunde inte rendera resultatet.")
        }

        return PlatformImage(cgImageRepresentation: outputCGImage)
    }

    /// Renderar BARA bakgrunden (ingen motivpixel alls) i `canvasSize` -
    /// den storlek motivet till slut hamnar i EFTER formbeskärning/
    /// positionering (`ShapeCropService.positioned(_:image:transform:)`),
    /// INTE `referenceImage`s egen storlek. Gör att bakgrunden alltid
    /// täcker HELA slutkanvasen oavsett var användaren panorerat motivet
    /// inom den (se `compositeOverCanvas(subject:backgroundFill:)` och
    /// `buggs.md`) - till skillnad från `composite(_:background:
    /// foregroundImage:)` ovan, som bakgrundslägger mot HELA
    /// `foreground`/`foregroundImage`s egen (oframade) storlek.
    ///
    /// - Parameter referenceImage: Källan `.blurredOriginal` blurrar - den
    ///   OBESKURNA bilden (efter filter/justeringar), inte motivurklippet.
    ///   Oanvänd av övriga stilar.
    public func backgroundFill(_ style: BackgroundStyle, referenceImage: CGImage, canvasSize: CGSize) throws -> PlatformImage {
        let backgroundCI = try makeBackgroundImage(style, original: CIImage(cgImage: referenceImage), extent: CGRect(origin: .zero, size: canvasSize))
        let context = SharedCIContext.shared
        guard let cgImage = context.createCGImage(backgroundCI, from: CGRect(origin: .zero, size: canvasSize)) else {
            throw RemovalError(message: "Kunde inte rendera bakgrunden.")
        }
        return PlatformImage(cgImageRepresentation: cgImage)
    }

    /// Lägger `subject` (redan formbeskuret/positionerat, med sin EGEN
    /// alfakanal - genomskinligt både där motivet klipptes bort OCH där
    /// panoreringen lämnat en kant av kanvasen exponerad, se
    /// `ShapeCropService.positioned(_:image:transform:)`) rakt ovanpå
    /// `backgroundFill` (redan i samma storlek, se `backgroundFill(_:
    /// referenceImage:canvasSize:)`). Ren "source over"-kompositering,
    /// ingen separat mask behövs - `subject`s egen alfa avgör var
    /// bakgrunden lyser igenom.
    public func compositeOverCanvas(subject: PlatformImage, backgroundFill: PlatformImage) throws -> PlatformImage {
        guard let subjectCG = subject.cgImageRepresentation, let backgroundCG = backgroundFill.cgImageRepresentation else {
            throw RemovalError(message: "Kunde inte läsa bilddata.")
        }
        let subjectCI = CIImage(cgImage: subjectCG)
        let backgroundCI = CIImage(cgImage: backgroundCG)

        guard let compositeFilter = CIFilter(name: "CISourceOverCompositing") else {
            throw RemovalError(message: "Kunde inte skapa bildfilter.")
        }
        compositeFilter.setValue(subjectCI, forKey: kCIInputImageKey)
        compositeFilter.setValue(backgroundCI, forKey: kCIInputBackgroundImageKey)

        let extent = CGRect(origin: .zero, size: subject.size)
        let context = SharedCIContext.shared
        guard let outputImage = compositeFilter.outputImage,
              let outputCGImage = context.createCGImage(outputImage, from: extent) else {
            throw RemovalError(message: "Kunde inte rendera resultatet.")
        }
        return PlatformImage(cgImageRepresentation: outputCGImage)
    }

    private func makeBackgroundImage(_ style: BackgroundStyle, original: CIImage, extent: CGRect) throws -> CIImage {
        switch style {
        case .transparent:
            return CIImage(color: .clear).cropped(to: extent)

        case .color(let cgColor):
            return CIImage(color: CIColor(cgColor: cgColor)).cropped(to: extent)

        case .gradient(let start, let end, let startPoint, let endPoint):
            guard let gradientFilter = CIFilter(name: "CILinearGradient") else {
                throw RemovalError(message: "Kunde inte skapa bildfilter.")
            }
            // Enhetskoordinater (y nedåt) -> CoreImage (y uppåt) i `extent`.
            func point(_ p: CGPoint) -> CIVector {
                CIVector(x: extent.minX + p.x * extent.width, y: extent.minY + (1 - p.y) * extent.height)
            }
            gradientFilter.setValue(point(startPoint), forKey: "inputPoint0")
            gradientFilter.setValue(point(endPoint), forKey: "inputPoint1")
            gradientFilter.setValue(CIColor(cgColor: start), forKey: "inputColor0")
            gradientFilter.setValue(CIColor(cgColor: end), forKey: "inputColor1")
            guard let gradient = gradientFilter.outputImage else {
                throw RemovalError(message: "Kunde inte skapa bildfilter.")
            }
            return gradient.cropped(to: extent)

        case .blurredOriginal(let radius):
            guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
                throw RemovalError(message: "Kunde inte skapa oskärpefilter.")
            }
            // Bilden kläms fast över hela ytan innan oskärpan, annars blir
            // kanterna genomskinliga eftersom CIGaussianBlur läser utanför
            // bildens ursprungliga gränser.
            blurFilter.setValue(original.clampedToExtent(), forKey: kCIInputImageKey)
            blurFilter.setValue(radius, forKey: kCIInputRadiusKey)
            guard let blurred = blurFilter.outputImage else {
                throw RemovalError(message: "Kunde inte skapa oskärpan.")
            }
            // Beskärningsfönstret CENTRERAS inom `original`s egna gränser
            // istället för att bara beskäras vid origo - `extent` är inte
            // alltid `original.extent` längre (se `backgroundFill(_:
            // referenceImage:canvasSize:)`, som skickar in slutkanvasens,
            // ofta mindre, kvadratiska storlek) - annars skulle en
            // liggande/stående bilds kvadratiska oskärpe-bakgrund bli
            // beskuren i ett hörn istället för mitten.
            let dx = (original.extent.width - extent.width) / 2
            let dy = (original.extent.height - extent.height) / 2
            let centeredExtent = CGRect(x: original.extent.minX + dx, y: original.extent.minY + dy, width: extent.width, height: extent.height)
            let cropped = blurred.cropped(to: centeredExtent)
            return cropped.transformed(by: CGAffineTransform(translationX: extent.minX - centeredExtent.minX, y: extent.minY - centeredExtent.minY))

        case .custom(let customImage, let transform):
            guard let customCG = customImage.cgImageRepresentation else {
                throw RemovalError(message: "Kunde inte läsa den valda bakgrundsbilden.")
            }
            // `allowsExposedEdges: true` - användaren får medvetet panorera
            // bakgrundsbilden så en kant av `extent` blottas (se
            // `CanvasTransform.scaledToFill`) istället för att den alltid
            // tvingas täcka hela ytan. De blottade pixlarna blir
            // genomskinliga i den returnerade bilden - både `composite()`s
            // `CIBlendWithMask` (visar `backgroundCI` rakt av där masken
            // säger "inte motiv") och `compositeOverCanvas`s raka
            // "source over" hanterar en genomskinlig bakgrund korrekt utan
            // vidare - i sista änden kvar som alfa i PNG, lagd mot vitt i
            // JPEG (`PlatformImage.exportData(as:)`).
            return transform.scaledToFill(CIImage(cgImage: customCG), target: extent, allowsExposedEdges: true)
        }
    }
}
