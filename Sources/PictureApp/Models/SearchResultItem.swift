import Foundation
import Photos

struct SearchResultItem: Identifiable, Hashable {
    let id: String
    let title: String
    let thumbnailURL: URL?
    let fullImageURL: URL?
    let localAsset: PHAsset?

    static func == (lhs: SearchResultItem, rhs: SearchResultItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
