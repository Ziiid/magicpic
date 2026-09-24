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
    @Published public var processedImage: PlatformImage?
    @Published public var isLoadingDetail = false
    @Published public var isProcessing = false
    @Published public var backgroundStyle: BackgroundOption = .transparent
    @Published public var outputShape: OutputShape = .rectangle
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
        backgroundStyle = .transparent
        outputShape = .rectangle

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
        backgroundStyle = .transparent
        outputShape = .rectangle
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
            guard let image = PlatformImage(data: data) else {
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
        let reusableMask = (cachedMaskSource === original) ? cachedMask : nil

        backgroundGeneration += 1
        let generation = backgroundGeneration

        Task.detached(priority: .userInitiated) { [backgroundRemoval, shapeCrop] in
            do {
                let mask = try reusableMask ?? backgroundRemoval.generateMask(for: original)
                var result = try backgroundRemoval.composite(mask, background: style)
                result = try shapeCrop.apply(shape, to: result)
                await MainActor.run {
                    guard generation == self.backgroundGeneration else { return }
                    self.processedImage = result
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

    /// Byter bakgrundsval. Om ett urklipp redan finns tillämpas den nya
    /// bakgrunden direkt ("byta bakgrund med ett klick"), annars sparas
    /// valet till nästa gång "Ta bort bakgrund" trycks.
    public func setBackgroundStyle(_ style: BackgroundOption) {
        backgroundStyle = style
        if processedImage != nil {
            removeBackground()
        }
    }

    /// Byter slutbildens form (kvadrat/cirkel/hexagon/...). Precis som
    /// bakgrundsvalet tillämpas det direkt om ett urklipp redan finns.
    public func setOutputShape(_ shape: OutputShape) {
        outputShape = shape
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
        backgroundStyle = .transparent
        outputShape = .rectangle
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
        guard let image = PlatformImage(data: data) else {
            throw LoadImageError.invalidImageData
        }
        return image
    }

    private enum LoadImageError: LocalizedError {
        case invalidImageData
        var errorDescription: String? { "Filen var inte en giltig bild." }
    }

    public func save() {
        guard let image = processedImage ?? originalImage else { return }
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
