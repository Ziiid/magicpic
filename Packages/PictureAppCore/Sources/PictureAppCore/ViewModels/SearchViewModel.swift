import SwiftUI

@MainActor
public final class SearchViewModel: ObservableObject {
    @Published public var query: String = ""
    @Published public var sourceKind: ImageSourceKind = .web
    @Published public var results: [SearchResultItem] = []
    @Published public var isSearching = false
    @Published public var errorMessage: String?

    @Published public var selectedItem: SearchResultItem?
    @Published public var originalImage: PlatformImage?
    // Motivet mot vald bakgrund, men INTE formbeskuret ännu (till skillnad
    // från `processedImage`) - källan för den inbäddade formramningen
    // (`SubjectFramingCanvas`), så man ser rätt bakgrund medan man
    // positionerar istället för det obehandlade originalet. Annars ser det
    // ut som att bakgrunden "kommer tillbaka" så fort man börjar justera
    // positionen (rapporterat 2026-09-25).
    @Published public var compositedImage: PlatformImage?
    @Published public var processedImage: PlatformImage?
    // Originalet med `photoFilter` + `imageAdjustments` tillämpade, men
    // INNAN Vision/bakgrund/form - ren, billig CoreImage-förhandsvisning
    // (ingen Vision-körning) så man ser effekten direkt, även innan man
    // någonsin bett om bakgrundsborttagning. Se `refreshEditPreview()`.
    @Published public var adjustedPreviewImage: PlatformImage?
    @Published public var isLoadingDetail = false
    @Published public var isProcessing = false
    @Published public var backgroundStyle: BackgroundOption = .transparent
    @Published public var photoFilter: PhotoFilter = .none
    @Published public var imageAdjustments: ImageAdjustments = .identity
    // Kvadrat, inte rektangel, är standard - annars finns ingen ram att
    // dra/zooma/vrida motivet inom direkt när bilden laddats in (se
    // `SubjectFramingCanvas` i DetailPanel.swift, verksam omedelbart, inte
    // gated bakom att välja bort bakgrund/byta bakgrund).
    @Published public var outputShape: OutputShape = .square
    @Published public var outputShapeTransform: CanvasTransform = .identity
    @Published public var backgroundPositioningRequest: BackgroundPositioningRequest?
    @Published public var maskEditingRequest: MaskEditingRequest?

    public struct BackgroundPositioningRequest: Identifiable {
        public let id = UUID()
        public let image: PlatformImage
        public let initialTransform: CanvasTransform
    }

    public struct MaskEditingRequest: Identifiable {
        public let id = UUID()
        public let baseImage: PlatformImage
        public let editableMask: EditableMask
    }

    public let settings: SettingsStore
    private let exporter: ImageExporter
    private let unsplashService = UnsplashImageSearchService()
    private let backgroundRemoval = BackgroundRemovalService()
    private let shapeCrop = ShapeCropService()
    private let imageAdjustment = ImageAdjustmentService()
    private let photoFilterService = PhotoFilterService()
    // Ökas för varje refreshEditPreview()-anrop så att en sen, ren
    // förhandsvisningskörning (utan Vision) inte skriver över en nyare -
    // samma mönster som `backgroundGeneration`.
    private var adjustmentGeneration = 0

    // Cachar den dyra Vision-masken per bild så att byte av bakgrundsstil
    // bara behöver köra om den billiga kompositeringen.
    private var cachedMask: BackgroundRemovalService.ForegroundMask?
    private var cachedMaskSource: PlatformImage?
    // Ökas för varje removeBackground()-anrop så att ett sent svar från ett
    // äldre anrop (t.ex. vid snabba klick i färgväljaren) inte skriver över
    // resultatet av ett nyare.
    private var backgroundGeneration = 0

    public init(settings: SettingsStore, exporter: ImageExporter) {
        self.settings = settings
        self.exporter = exporter
    }

    public func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        errorMessage = nil
        isSearching = true
        results = []
        selectedItem = nil
        originalImage = nil
        processedImage = nil
        compositedImage = nil
        adjustedPreviewImage = nil
        backgroundStyle = .transparent
        photoFilter = .none
        imageAdjustments = .identity
        outputShape = .square
        outputShapeTransform = .identity

        Task {
            do {
                results = try await unsplashService.search(
                    query: trimmed,
                    accessKey: settings.unsplashAccessKey
                )
                if results.isEmpty { errorMessage = "Inga bilder hittades." }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    public func select(_ item: SearchResultItem) {
        selectedItem = item
        originalImage = nil
        processedImage = nil
        compositedImage = nil
        adjustedPreviewImage = nil
        backgroundStyle = .transparent
        photoFilter = .none
        imageAdjustments = .identity
        outputShape = .square
        outputShapeTransform = .identity
        errorMessage = nil
        isLoadingDetail = true

        Task {
            originalImage = await loadFullImage(for: item)
            isLoadingDetail = false
        }
    }

    private func loadFullImage(for item: SearchResultItem) async -> PlatformImage? {
        guard let url = item.fullImageURL else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = PlatformImage.normalizedOrientation(from: data) else {
                errorMessage = "Filen var inte en giltig bild."
                return nil
            }
            return image
        } catch {
            errorMessage = "Kunde inte hämta bilden i full storlek: \(error.localizedDescription)"
            return nil
        }
    }

    public func removeBackground() {
        guard let original = originalImage else { return }
        isProcessing = true
        errorMessage = nil
        let style = backgroundStyle.serviceStyle
        let shape = outputShape
        let shapeTransform = outputShapeTransform
        let filter = photoFilter
        let adjustments = imageAdjustments
        let reusableMask = (cachedMaskSource === original) ? cachedMask : nil

        backgroundGeneration += 1
        let generation = backgroundGeneration

        Task.detached(priority: .userInitiated) { [backgroundRemoval, shapeCrop, photoFilterService, imageAdjustment] in
            do {
                // Masken cachas mot den OJUSTERADE originalbilden - varken
                // ett filter eller en bildkorrigering ändrar motivets
                // kontur, bara dess färger, så samma mask är fortfarande
                // giltig och Vision behöver inte köras om bara för det.
                let mask = try reusableMask ?? backgroundRemoval.generateMask(for: original)
                let filtered = try photoFilterService.apply(filter, to: original)
                let adjustedCG = try imageAdjustment.apply(adjustments, to: filtered).cgImageRepresentation
                let composited = try backgroundRemoval.composite(mask, background: style, foregroundImage: adjustedCG)
                let shaped = try shapeCrop.apply(shape, to: composited, transform: shapeTransform)
                await MainActor.run {
                    guard generation == self.backgroundGeneration else { return }
                    self.compositedImage = composited
                    self.processedImage = shaped
                    self.isProcessing = false
                    self.cachedMask = mask
                    self.cachedMaskSource = original
                }
            } catch {
                await MainActor.run {
                    guard generation == self.backgroundGeneration else { return }
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }

    /// Kastar bort allt bakgrunds-/form-/positioneringsval och går tillbaka
    /// till den obehandlade originalbilden - en "ångra allt"-knapp. Ökar
    /// `backgroundGeneration` så en ev. redan pågående `removeBackground()`
    /// inte skriver över återställningen när den sedan blir klar.
    public func restoreOriginal() {
        backgroundGeneration += 1
        adjustmentGeneration += 1
        processedImage = nil
        compositedImage = nil
        adjustedPreviewImage = nil
        backgroundStyle = .transparent
        photoFilter = .none
        imageAdjustments = .identity
        outputShape = .square
        outputShapeTransform = .identity
        isProcessing = false
        errorMessage = nil
    }

    /// Byter bakgrundsval och tillämpar det direkt ("byta bakgrund med ett
    /// klick") - körs ALLTID om, inte bara när ett urklipp redan finns.
    /// Annars sparades valet bara tyst utan synlig effekt om man ännu inte
    /// hunnit trycka "Ta bort bakgrund" en första gång, vilket kändes som
    /// att vissa val "inte fungerade" (upptäckt 2026-09-25). `removeBackground()`
    /// no-opar redan ofarligt om ingen bild är inläst.
    public func setBackgroundStyle(_ style: BackgroundOption) {
        backgroundStyle = style
        removeBackground()
    }

    /// Byter valt filter (färdig bildstil, t.ex. svartvitt/röntgen/sepia)
    /// och tillämpar det direkt - av samma anledning och på samma sätt som
    /// `setImageAdjustments` nedan.
    public func setPhotoFilter(_ filter: PhotoFilter) {
        photoFilter = filter
        refreshEditPreview()
        if processedImage != nil {
            removeBackground()
        }
    }

    /// Uppdaterar bildkorrigeringarna (ljusstyrka/kontrast/mättnad/
    /// temperatur/highlights/shadows/skärpa/brusreducering/vinjett).
    /// Räknar ALLTID om en ren, billig CoreImage-förhandsvisning direkt
    /// (`adjustedPreviewImage`, ingen Vision inblandad) så man ser effekten
    /// omedelbart även innan bakgrunden någonsin bearbetats. Komponerar
    /// dessutom om det FULLA resultatet, men bara om ett urklipp redan
    /// finns - av samma anledning som `commitOutputShapeTransform`: att
    /// bara justera skärpa/ljusstyrka/filter på originalet ska inte tyst
    /// trigga en riktig bakgrundsborttagning med standardbakgrunden.
    public func setImageAdjustments(_ adjustments: ImageAdjustments) {
        imageAdjustments = adjustments
        refreshEditPreview()
        if processedImage != nil {
            removeBackground()
        }
    }

    /// Räknar om `adjustedPreviewImage` - filter + bildkorrigeringar
    /// tillämpade på originalet, ingen Vision inblandad. Delad av
    /// `setPhotoFilter` och `setImageAdjustments`.
    private func refreshEditPreview() {
        guard let original = originalImage else { return }
        let filter = photoFilter
        let adjustments = imageAdjustments

        adjustmentGeneration += 1
        let generation = adjustmentGeneration

        Task.detached(priority: .userInitiated) { [photoFilterService, imageAdjustment] in
            guard let filtered = try? photoFilterService.apply(filter, to: original),
                  let preview = try? imageAdjustment.apply(adjustments, to: filtered) else { return }
            await MainActor.run {
                guard generation == self.adjustmentGeneration else { return }
                self.adjustedPreviewImage = preview
            }
        }
    }

    /// Byter slutbildens form (kvadrat/cirkel/hexagon/...) och tillämpar den
    /// direkt, av samma anledning som `setBackgroundStyle`.
    /// Positioneringen (pan/zoom) i `outputShapeTransform` behålls oförändrad
    /// - den avser var i motivet formen läggs, inte formen själv.
    public func setOutputShape(_ shape: OutputShape) {
        outputShape = shape
        removeBackground()
    }

    /// Anropas när användaren släpper en dra-/nyp-/rotationsgest i den
    /// inbäddade formramningen (`SubjectFramingCanvas`) - `outputShapeTransform`
    /// är redan uppdaterad via bindningen dit. Körs BARA om bearbetning
    /// redan skett minst en gång tidigare (till skillnad från
    /// `setBackgroundStyle`/`setOutputShape`, som alltid kör om) - annars
    /// skulle bara det att panorera/zooma/rotera för att komponera bilden,
    /// INNAN man bett om bakgrundsborttagning över huvud taget, tyst
    /// trigga en riktig Vision-körning med standardbakgrunden
    /// (genomskinlig), vilket upplevdes som att "bakgrunden försvinner när
    /// jag bara drar i bilden" (upptäckt 2026-09-25).
    public func commitOutputShapeTransform() {
        if processedImage != nil {
            removeBackground()
        }
    }

    /// Läser in en bildfil som egen bakgrund (via filväljaren i DetailPanel)
    /// och öppnar positioneraren så användaren kan panorera/zooma den innan
    /// den tillämpas.
    public func setCustomBackground(from url: URL) async {
        do {
            let image = try await Self.loadImage(from: url)
            backgroundPositioningRequest = BackgroundPositioningRequest(image: image, initialTransform: .identity)
        } catch {
            errorMessage = "Kunde inte läsa bakgrundsbilden: \(error.localizedDescription)"
        }
    }

    /// Öppnar positioneraren igen för den bakgrundsbild som redan är vald,
    /// med dess nuvarande pan/zoom som utgångspunkt.
    public func beginRepositioningCustomBackground() {
        guard case .custom(let image, let transform) = backgroundStyle else { return }
        backgroundPositioningRequest = BackgroundPositioningRequest(image: image, initialTransform: transform)
    }

    public func confirmCustomBackground(image: PlatformImage, transform: CanvasTransform) {
        backgroundPositioningRequest = nil
        setBackgroundStyle(.custom(image, transform: transform))
    }

    public func cancelCustomBackgroundPositioning() {
        backgroundPositioningRequest = nil
    }

    /// Öppnar penselredigeraren för den senast beräknade masken. Kräver att
    /// "Ta bort bakgrund" redan körts en gång för aktuell bild.
    public func beginMaskEditing() {
        guard let original = originalImage,
              let cached = cachedMask,
              cachedMaskSource === original else { return }
        maskEditingRequest = MaskEditingRequest(baseImage: original, editableMask: EditableMask(copying: cached.mask))
    }

    /// Tar den redigerade masken från penselverktyget, cachar den som den
    /// nya masken för bilden, och komponerar om med aktuell bakgrundsstil.
    public func applyEditedMask(_ editableMask: EditableMask) {
        guard let cached = cachedMask else { return }
        cachedMask = BackgroundRemovalService.ForegroundMask(original: cached.original, mask: editableMask.pixelBuffer)
        cachedMaskSource = originalImage
        maskEditingRequest = nil
        removeBackground()
    }

    public func cancelMaskEditing() {
        maskEditingRequest = nil
    }

    /// Läser in en bild som släppts (drag-and-drop) eller valts via
    /// filväljaren för bearbetning, utan att den kommer från ett sökresultat.
    public func loadImportedImage(from url: URL) async {
        errorMessage = nil
        isLoadingDetail = true
        do {
            let image = try await Self.loadImage(from: url)
            loadImportedImage(image, name: url.lastPathComponent)
        } catch {
            errorMessage = "Kunde inte läsa den släppta bilden: \(error.localizedDescription)"
        }
        isLoadingDetail = false
    }

    public func loadImportedImage(_ image: PlatformImage, name: String) {
        selectedItem = SearchResultItem(
            id: "imported-\(UUID().uuidString)",
            title: name,
            thumbnailURL: nil,
            fullImageURL: nil
        )
        originalImage = image
        processedImage = nil
        compositedImage = nil
        adjustedPreviewImage = nil
        backgroundStyle = .transparent
        photoFilter = .none
        imageAdjustments = .identity
        outputShape = .square
        outputShapeTransform = .identity
        errorMessage = nil
        isLoadingDetail = false
    }

    private static func loadImage(from url: URL) async throws -> PlatformImage {
        let data: Data
        if url.isFileURL {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            data = try Data(contentsOf: url)
        } else {
            (data, _) = try await URLSession.shared.data(from: url)
        }
        guard let image = PlatformImage.normalizedOrientation(from: data) else {
            throw LoadImageError.invalidImageData
        }
        return image
    }

    private enum LoadImageError: LocalizedError {
        case invalidImageData
        var errorDescription: String? { "Filen var inte en giltig bild." }
    }

    public func save() {
        // Faller tillbaka till `adjustedPreviewImage` (inte bara
        // `originalImage`) - annars skulle bildkorrigeringar man gjort men
        // ALDRIG kört bakgrundsborttagning för (processedImage fortfarande
        // nil) sparas bort tyst.
        guard let image = processedImage ?? adjustedPreviewImage ?? originalImage else { return }
        let safeName = (selectedItem?.title ?? "bild")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".jpg", with: "")
            .replacingOccurrences(of: ".jpeg", with: "")
            .replacingOccurrences(of: ".png", with: "")

        Task {
            do {
                try await exporter.export(image: image, suggestedName: safeName + ".png")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
