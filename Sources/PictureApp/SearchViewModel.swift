import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var sourceKind: ImageSourceKind = .web
    @Published var results: [SearchResultItem] = []
    @Published var isSearching = false
    @Published var errorMessage: String?

    @Published var selectedItem: SearchResultItem?
    @Published var originalImage: NSImage?
    @Published var processedImage: NSImage?
    @Published var isLoadingDetail = false
    @Published var isProcessing = false

    let settings: SettingsStore
    private let unsplashService = UnsplashImageSearchService()
    private let photosService = PhotosSearchService()
    private let backgroundRemoval = BackgroundRemovalService()

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func search() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        errorMessage = nil
        isSearching = true
        results = []
        selectedItem = nil
        originalImage = nil
        processedImage = nil

        Task {
            switch sourceKind {
            case .web:
                guard !trimmed.isEmpty else {
                    isSearching = false
                    return
                }
                do {
                    results = try await unsplashService.search(
                        query: trimmed,
                        accessKey: settings.unsplashAccessKey
                    )
                    if results.isEmpty { errorMessage = "Inga bilder hittades." }
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .photos:
                results = await photosService.search(query: trimmed)
                if results.isEmpty { errorMessage = "Inga bilder hittades i Foton. Sökningen matchar filnamn och albumnamn." }
            }
            isSearching = false
        }
    }

    func select(_ item: SearchResultItem) {
        selectedItem = item
        originalImage = nil
        processedImage = nil
        errorMessage = nil
        isLoadingDetail = true

        Task {
            originalImage = await loadFullImage(for: item)
            isLoadingDetail = false
        }
    }

    private func loadFullImage(for item: SearchResultItem) async -> NSImage? {
        if let asset = item.localAsset {
            return await photosService.loadImage(for: asset, targetSize: CGSize(width: 1600, height: 1600))
        }
        guard let url = item.fullImageURL else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = NSImage(data: data) else {
                errorMessage = "Filen var inte en giltig bild."
                return nil
            }
            return image
        } catch {
            errorMessage = "Kunde inte hämta bilden i full storlek: \(error.localizedDescription)"
            return nil
        }
    }

    func removeBackground() {
        guard let original = originalImage else { return }
        isProcessing = true
        errorMessage = nil

        Task.detached(priority: .userInitiated) { [backgroundRemoval] in
            do {
                let result = try backgroundRemoval.removeBackground(from: original)
                await MainActor.run {
                    self.processedImage = result
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }

    func save() {
        guard let image = processedImage ?? originalImage else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        let safeName = (selectedItem?.title ?? "bild")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".jpg", with: "")
            .replacingOccurrences(of: ".jpeg", with: "")
            .replacingOccurrences(of: ".png", with: "")
        panel.nameFieldStringValue = safeName + ".png"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let data = image.pngData() else {
                self.errorMessage = "Kunde inte skapa PNG-data."
                return
            }
            do {
                try data.write(to: url)
            } catch {
                self.errorMessage = "Kunde inte spara filen: \(error.localizedDescription)"
            }
        }
    }
}
