import CoreImage
import CoreGraphics

/// Tillämpar en färdig bildstil (`PhotoFilter`) på en bild, ren CoreImage -
/// körs INNAN `ImageAdjustments` och Vision-analysen (se
/// `SearchViewModel.removeBackground()`), som ett första, valfritt
/// "stil"-lager. Bygger uteslutande på Apples inbyggda CIFilter-namn (samma
/// filter Bilder-appens eget filterval använder), inga uppgissade/
/// odokumenterade filter.
///
/// De flesta stilarna är RENA färgfilter (samma dimensioner in som ut) och
/// hanteras helt av `colorLook(_:to:)`. Polaroid/Fotoautomat är annorlunda -
/// de bygger också om själva LAYOUTEN (vit ram, flerbilds-remsa), vilket
/// medvetet är en SEPARAT metod (`layoutWrap(_:wrapping:)`) istället för en
/// del av samma stora switch: `SearchViewModel.applyPipeline` behöver klämma
/// in bakgrundskompositering + formbeskärning MELLAN färglooken och
/// lager-ombyggnaden (se `SearchViewModel.applyPipeline`s dokumentation för
/// varför - annars hamnar Visions mask fel mot den nya, större bilden).
/// `apply(_:to:)` kedjar bara ihop de två för de anrop (förhandsvisning utan
/// Vision, miniatyrer) som vill ha hela resultatet i ett svep.
public struct PhotoFilterService {
    public struct FilterError: LocalizedError {
        let message: String
        // Se `BackgroundRemovalService.RemovalError`s motsvarande kommentar
        // - EN lokaliseringspunkt istället för att skriva om varje `throw`.
        public var errorDescription: String? {
            String(localized: String.LocalizationValue(message), bundle: .module, locale: AppLanguage.current.locale)
        }
    }

    public init() {}

    public func apply(_ filter: PhotoFilter, to image: PlatformImage) throws -> PlatformImage {
        let looked = try colorLook(filter, to: image)
        return try layoutWrap(filter, wrapping: looked)
    }

    public func colorLook(_ filter: PhotoFilter, to image: PlatformImage) throws -> PlatformImage {
        guard filter != .none else { return image }

        guard let cgImage = image.cgImageRepresentation else {
            throw FilterError(message: "Kunde inte läsa bilddata.")
        }

        let source = CIImage(cgImage: cgImage)
        let extent = source.extent
        let output: CIImage

        switch filter {
        case .none:
            return image

        case .blackAndWhite:
            output = try Self.runFilter("CIPhotoEffectNoir", image: source)

        case .sepia:
            guard let ciFilter = CIFilter(name: "CISepiaTone") else {
                throw FilterError(message: "Kunde inte skapa sepiafilter.")
            }
            ciFilter.setValue(source, forKey: kCIInputImageKey)
            ciFilter.setValue(0.85, forKey: kCIInputIntensityKey)
            guard let sepiaOutput = ciFilter.outputImage else {
                throw FilterError(message: "Kunde inte tillämpa sepia.")
            }
            output = sepiaOutput

        case .xray:
            // Gråskala + inverterade färger - klassisk röntgenbilds-känsla.
            let mono = try Self.runFilter("CIPhotoEffectMono", image: source)
            output = try Self.runFilter("CIColorInvert", image: mono)

        case .chrome:
            output = try Self.runFilter("CIPhotoEffectChrome", image: source)

        case .fade:
            output = try Self.runFilter("CIPhotoEffectFade", image: source)

        case .comic:
            output = try Self.runFilter("CIComicEffect", image: source)

        case .thermal:
            // Ingen inbyggd "termisk" CIFilter finns - byggs av gråskala
            // (CIColorControls, mättnad 0) följt av CIFalseColor, som
            // mappar mörkt/ljust mot en lila→gul gradient likt en
            // värmekamerabild.
            guard let grayscaleFilter = CIFilter(name: "CIColorControls") else {
                throw FilterError(message: "Kunde inte skapa värmekamerafiltret.")
            }
            grayscaleFilter.setValue(source, forKey: kCIInputImageKey)
            grayscaleFilter.setValue(0, forKey: kCIInputSaturationKey)
            guard let grayscale = grayscaleFilter.outputImage,
                  let falseColorFilter = CIFilter(name: "CIFalseColor") else {
                throw FilterError(message: "Kunde inte skapa värmekamerafiltret.")
            }
            falseColorFilter.setValue(grayscale, forKey: kCIInputImageKey)
            falseColorFilter.setValue(CIColor(red: 0.05, green: 0.0, blue: 0.3), forKey: "inputColor0")
            falseColorFilter.setValue(CIColor(red: 1.0, green: 0.9, blue: 0.1), forKey: "inputColor1")
            guard let thermalOutput = falseColorFilter.outputImage else {
                throw FilterError(message: "Kunde inte tillämpa värmekameraeffekten.")
            }
            output = thermalOutput

        case .poster:
            guard let ciFilter = CIFilter(name: "CIColorPosterize") else {
                throw FilterError(message: "Kunde inte skapa posterfilter.")
            }
            ciFilter.setValue(source, forKey: kCIInputImageKey)
            ciFilter.setValue(6, forKey: "inputLevels")
            guard let posterOutput = ciFilter.outputImage else {
                throw FilterError(message: "Kunde inte tillämpa poster-effekten.")
            }
            output = posterOutput

        case .instant:
            output = try Self.runFilter("CIPhotoEffectInstant", image: source)

        // Samma inbyggda "Photo Effect"-familj som Krom/Blekt/Polaroid/
        // Svartvitt (Noir) ovan - Process (kall, mättad "cross-process"-
        // känsla), Tonal (flackare, mindre kontrastrik svartvitt än Noir)
        // och Transfer (varm, lätt urblekt filmkänsla) är de tre kvarvarande
        // färdiga stilarna i den familjen som appen ännu inte erbjöd.
        case .process:
            output = try Self.runFilter("CIPhotoEffectProcess", image: source)

        case .tonal:
            output = try Self.runFilter("CIPhotoEffectTonal", image: source)

        case .transfer:
            output = try Self.runFilter("CIPhotoEffectTransfer", image: source)

        case .vignette:
            // `CIVignetteEffect` (INTE äldre `CIVignette`, vars radie/
            // intensitet är svåra att få ett synligt resultat av oavsett
            // bildstorlek) - kräver `inputCenter` som bildens mittpunkt och
            // en radie räknad från bildens FAKTISKA dimensioner, annars blir
            // mörkläggningen antingen osynlig eller täcker hela bilden
            // beroende på källbildens upplösning.
            guard let ciFilter = CIFilter(name: "CIVignetteEffect") else {
                throw FilterError(message: "Kunde inte skapa vinjettfiltret.")
            }
            ciFilter.setValue(source, forKey: kCIInputImageKey)
            ciFilter.setValue(CIVector(x: extent.midX, y: extent.midY), forKey: "inputCenter")
            ciFilter.setValue(min(extent.width, extent.height) * 0.75, forKey: "inputRadius")
            ciFilter.setValue(1.0, forKey: "inputIntensity")
            guard let vignetteOutput = ciFilter.outputImage else {
                throw FilterError(message: "Kunde inte tillämpa vinjetteffekten.")
            }
            output = vignetteOutput

        case .negative:
            // Fullfärgs-negativ - samma `CIColorInvert` som `.xray` redan
            // använder på en avmättad bild ovan, men här på originalfärgerna
            // rakt av istället, för ett riktigt fotonegativ-utseende.
            output = try Self.runFilter("CIColorInvert", image: source)

        case .silhouette:
            // Alla färgkanaler nollas, alfakanalen behålls - ren svart
            // siluett. Lika med hela bilden svart om ingen bakgrunds-
            // borttagning körts (rektangeln har ingen genomskinlighet), så
            // `SearchViewModel.setPhotoFilter` tvingar fram en körning när
            // stilen väljs. `CIColorMatrix` är ett riktigt CIFilter-namn.
            guard let ciFilter = CIFilter(name: "CIColorMatrix") else {
                throw FilterError(message: "Kunde inte skapa siluettfilter.")
            }
            ciFilter.setValue(source, forKey: kCIInputImageKey)
            ciFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
            ciFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
            ciFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
            ciFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            ciFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
            guard let silhouetteOutput = ciFilter.outputImage else {
                throw FilterError(message: "Kunde inte tillämpa siluetten.")
            }
            output = silhouetteOutput

        // Polaroid/Fotoautomats FÄRGLOOK - bara tonen, samma dimensioner in
        // som ut. Själva ramen/remsan byggs separat av `layoutWrap` nedan,
        // EFTER att bakgrund/formbeskärning redan körts (se filens
        // dokumentationskommentar högst upp).
        case .polaroid:
            output = try Self.polaroidColorLook(source)

        case .photobooth:
            // "Originalfärg" per uppdraget - ingen tonändring alls här,
            // bara layouten (remsan) skiljer den från `.none`.
            output = source

        case .photoboothMono:
            output = try Self.photoboothMonoLook(source)
        }

        let context = CIContext()
        guard let outputCGImage = context.createCGImage(output, from: extent) else {
            throw FilterError(message: "Kunde inte rendera det filtrerade resultatet.")
        }
        return PlatformImage(cgImageRepresentation: outputCGImage)
    }

    /// Bygger om LAYOUTEN för Polaroid/Fotoautomat (vit ram, flerbilds-
    /// remsa) - för alla andra stilar är det här en no-op. Tar och lämnar
    /// `PlatformImage` (inte `CIImage`) eftersom canvasen har ANDRA
    /// dimensioner än indatan, till skillnad från `colorLook` ovan.
    public func layoutWrap(_ filter: PhotoFilter, wrapping image: PlatformImage) throws -> PlatformImage {
        switch filter {
        case .polaroid:
            return try Self.framePolaroid(image)
        case .photobooth, .photoboothMono:
            return try Self.buildPhotoboothStrip(image)
        default:
            return image
        }
    }

    private static func runFilter(_ name: String, image: CIImage) throws -> CIImage {
        guard let ciFilter = CIFilter(name: name) else {
            // Fast, o-interpolerad nyckel + filternamnet konkatenerat
            // EFTER lokaliseringen - `FilterError.errorDescription` slår
            // upp HELA `message` som en nyckel (se dess kommentar), och ett
            // filternamn som varierar per anrop skulle aldrig matcha en
            // fast katalogpost.
            let prefix = String(localized: "Kunde inte skapa filtret", bundle: .module, locale: AppLanguage.current.locale)
            throw FilterError(message: "\(prefix) \(name).")
        }
        ciFilter.setValue(image, forKey: kCIInputImageKey)
        guard let output = ciFilter.outputImage else {
            throw FilterError(message: "Kunde inte tillämpa filtret.")
        }
        return output
    }

    /// Varmare ton, mjukare kontrast, lätt dämpad mättnad, mycket subtil
    /// grain - Polaroid-känslan INNAN ramen läggs på. `CIColorMatrix`
    /// (istället för t.ex. `CITemperatureAndTint`, vars temperatur-riktning
    /// är lätt att få fel utan att testa på enhet) ger en förutsägbar,
    /// deterministisk varm skjutning (mer rött, mindre blått).
    private static func polaroidColorLook(_ image: CIImage) throws -> CIImage {
        guard let colorFilter = CIFilter(name: "CIColorControls") else {
            throw FilterError(message: "Kunde inte skapa Polaroid-färgläget.")
        }
        colorFilter.setValue(image, forKey: kCIInputImageKey)
        colorFilter.setValue(0.88, forKey: kCIInputSaturationKey)
        colorFilter.setValue(0.94, forKey: kCIInputContrastKey)
        colorFilter.setValue(0.02, forKey: kCIInputBrightnessKey)
        guard let softened = colorFilter.outputImage else {
            throw FilterError(message: "Kunde inte tillämpa Polaroid-färgläget.")
        }

        guard let warmFilter = CIFilter(name: "CIColorMatrix") else {
            throw FilterError(message: "Kunde inte skapa den varma tonen.")
        }
        warmFilter.setValue(softened, forKey: kCIInputImageKey)
        warmFilter.setValue(CIVector(x: 1.05, y: 0, z: 0, w: 0), forKey: "inputRVector")
        warmFilter.setValue(CIVector(x: 0, y: 1.0, z: 0, w: 0), forKey: "inputGVector")
        warmFilter.setValue(CIVector(x: 0, y: 0, z: 0.93, w: 0), forKey: "inputBVector")
        warmFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        warmFilter.setValue(CIVector(x: 0.015, y: 0.006, z: -0.015, w: 0), forKey: "inputBiasVector")
        guard let warmed = warmFilter.outputImage else {
            throw FilterError(message: "Kunde inte tillämpa den varma tonen.")
        }

        guard let noiseFilter = CIFilter(name: "CIRandomGenerator"), let noise = noiseFilter.outputImage else {
            throw FilterError(message: "Kunde inte skapa grain-effekten.")
        }
        guard let grainAlpha = CIFilter(name: "CIColorMatrix") else {
            throw FilterError(message: "Kunde inte skapa grain-effekten.")
        }
        grainAlpha.setValue(noise.cropped(to: image.extent), forKey: kCIInputImageKey)
        grainAlpha.setValue(CIVector(x: 0, y: 0, z: 0, w: 0.04), forKey: "inputAVector")
        guard let subtleGrain = grainAlpha.outputImage else {
            throw FilterError(message: "Kunde inte tillämpa grain-effekten.")
        }

        return subtleGrain.composited(over: warmed)
    }

    /// Klassisk fotoautomat-känsla: högkontrast-svartvitt.
    private static func photoboothMonoLook(_ image: CIImage) throws -> CIImage {
        let mono = try Self.runFilter("CIPhotoEffectMono", image: image)
        guard let contrastFilter = CIFilter(name: "CIColorControls") else {
            throw FilterError(message: "Kunde inte skapa fotoautomat-filtret.")
        }
        contrastFilter.setValue(mono, forKey: kCIInputImageKey)
        contrastFilter.setValue(1.12, forKey: kCIInputContrastKey)
        guard let output = contrastFilter.outputImage else {
            throw FilterError(message: "Kunde inte tillämpa fotoautomat-filtret.")
        }
        return output
    }

    /// Bygger den vita/off-white Polaroid-ramen runt en redan förbehandlad
    /// bild - smal kant upptill/vänster/höger, tydligt tjockare nedtill.
    /// Ren CIImage-komposition (`CIImage(color:).cropped(to:)` +
    /// `.composited(over:)`, samma beprövade mönster som
    /// `PlatformImage.flattenedOverWhite()` redan använder) - INTE en
    /// handskriven `CGContext`-ritväg, för att inte introducera en ny,
    /// oprövad koordinat-/pixelformatsrisk (se `buggs.md` om varför den sortens
    /// antagande tidigare gått fel i det här projektet).
    private static func framePolaroid(_ image: PlatformImage) throws -> PlatformImage {
        guard let cgImage = image.cgImageRepresentation else {
            throw FilterError(message: "Kunde inte läsa bilddata för Polaroid-ramen.")
        }
        let photo = CIImage(cgImage: cgImage)
        let extent = photo.extent
        let width = extent.width
        let height = extent.height
        guard width > 0, height > 0 else { return image }

        let sideBorder = width * 0.045
        let topBorder = sideBorder
        let bottomBorder = height * 0.18
        let canvasExtent = CGRect(x: 0, y: 0, width: width + sideBorder * 2, height: height + topBorder + bottomBorder)

        let frameColor = CIImage(color: CIColor(cgColor: AppTheme.onAccentCGColor)).cropped(to: canvasExtent)
        let positioned = photo.transformed(by: CGAffineTransform(translationX: sideBorder, y: bottomBorder))
        let card = positioned.composited(over: frameColor)

        guard let outputCGImage = CIContext().createCGImage(card, from: canvasExtent) else {
            throw FilterError(message: "Kunde inte rendera Polaroid-ramen.")
        }
        return PlatformImage(cgImageRepresentation: outputCGImage)
    }

    /// Bygger fotoautomat-remsan: samma (redan förbehandlade) bild upprepad
    /// FYRA gånger, staplade vertikalt, med tunna mellanrum och en tydligt
    /// större marginal upptill/nedtill för klassisk fotoautomat-känsla.
    /// Cropen/positionen är MEDVETET identisk i alla fyra rutor (se
    /// uppdragets egen not om att det duger för första versionen) - bara en
    /// mikroskopisk, FASTA (inte slumpade) ljusstyrke-variation per ruta
    /// skiljer dem åt, så det känns som fyra separata exponeringar utan att
    /// riskera att någon ruta ser konstigt beskuren ut.
    private static func buildPhotoboothStrip(_ image: PlatformImage) throws -> PlatformImage {
        guard let cgImage = image.cgImageRepresentation else {
            throw FilterError(message: "Kunde inte läsa bilddata för fotoautomat-remsan.")
        }
        let cell = CIImage(cgImage: cgImage)
        let extent = cell.extent
        let width = extent.width
        let height = extent.height
        guard width > 0, height > 0 else { return image }

        let cellCount = 4
        let sideBorder = width * 0.05
        let gap = width * 0.03
        let outerVerticalMargin = width * 0.09

        let stripWidth = width + sideBorder * 2
        let stripHeight = height * CGFloat(cellCount) + gap * CGFloat(cellCount - 1) + outerVerticalMargin * 2
        let stripExtent = CGRect(x: 0, y: 0, width: stripWidth, height: stripHeight)

        let frameColor = CIImage(color: CIColor(cgColor: AppTheme.onAccentCGColor)).cropped(to: stripExtent)
        let brightnessDeltas: [Double] = [0.0, -0.012, 0.008, -0.006]

        var composed = frameColor
        for index in 0..<cellCount {
            let variedCell: CIImage
            if brightnessDeltas[index] == 0 {
                variedCell = cell
            } else {
                guard let brightnessFilter = CIFilter(name: "CIColorControls") else {
                    throw FilterError(message: "Kunde inte skapa fotoautomat-variationen.")
                }
                brightnessFilter.setValue(cell, forKey: kCIInputImageKey)
                brightnessFilter.setValue(brightnessDeltas[index], forKey: kCIInputBrightnessKey)
                guard let variedOutput = brightnessFilter.outputImage else {
                    throw FilterError(message: "Kunde inte skapa fotoautomat-variationen.")
                }
                variedCell = variedOutput
            }

            // Rutorna staplas UPPIFRÅN och ner (index 0 överst) - CIImages
            // koordinatsystem har origo NERE till vänster, så "avstånd
            // uppifrån" måste räknas om till ett y-värde underifrån.
            let distanceFromTop = outerVerticalMargin + CGFloat(index) * (height + gap)
            let y = stripHeight - distanceFromTop - height
            let positioned = variedCell.transformed(by: CGAffineTransform(translationX: sideBorder, y: y))
            composed = positioned.composited(over: composed)
        }

        guard let outputCGImage = CIContext().createCGImage(composed, from: stripExtent) else {
            throw FilterError(message: "Kunde inte rendera fotoautomat-remsan.")
        }
        return PlatformImage(cgImageRepresentation: outputCGImage)
    }
}
