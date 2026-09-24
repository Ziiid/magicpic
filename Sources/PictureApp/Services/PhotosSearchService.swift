import Photos
import AppKit

/// Söker bland bilder i användarens Foton-bibliotek.
///
/// OBS: Apples publika PhotoKit-API erbjuder ingen fri innehållsbaserad
/// bildsökning (t.ex. "hittar bilder som innehåller en hund") - den
/// funktionen är intern i Foton-appen. Den här tjänsten söker istället på:
///   - filnamn
///   - namn på album som matchar sökordet
/// Tom sökning listar de senaste bilderna.
@MainActor
final class PhotosSearchService {
    func requestAuthorizationIfNeeded() async -> Bool {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            return true
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return newStatus == .authorized || newStatus == .limited
        default:
            return false
        }
    }

    func search(query: String) async -> [SearchResultItem] {
        let granted = await requestAuthorizationIfNeeded()
        guard granted else { return [] }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        fetchOptions.fetchLimit = 600

        let allPhotos = PHAsset.fetchAssets(with: .image, options: fetchOptions)

        var matchingAlbumAssetIDs: Set<String> = []
        if !trimmed.isEmpty {
            let albumFetch = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
            albumFetch.enumerateObjects { collection, _, _ in
                guard let title = collection.localizedTitle,
                      title.localizedCaseInsensitiveContains(trimmed) else { return }
                let assets = PHAsset.fetchAssets(in: collection, options: nil)
                assets.enumerateObjects { asset, _, _ in
                    matchingAlbumAssetIDs.insert(asset.localIdentifier)
                }
            }
        }

        var results: [SearchResultItem] = []
        allPhotos.enumerateObjects { asset, _, stop in
            let filename = PHAssetResource.assetResources(for: asset).first?.originalFilename ?? ""
            let matchesQuery = trimmed.isEmpty
                || filename.localizedCaseInsensitiveContains(trimmed)
                || matchingAlbumAssetIDs.contains(asset.localIdentifier)

            if matchesQuery {
                results.append(
                    SearchResultItem(
                        id: "local-\(asset.localIdentifier)",
                        title: filename.isEmpty ? "Foto" : filename,
                        thumbnailURL: nil,
                        fullImageURL: nil,
                        localAsset: asset
                    )
                )
            }
            if results.count >= 80 { stop.pointee = true }
        }
        return results
    }

    func loadImage(for asset: PHAsset, targetSize: CGSize) async -> NSImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = .exact

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}
