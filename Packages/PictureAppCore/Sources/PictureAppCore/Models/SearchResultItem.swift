import Foundation

public struct SearchResultItem: Identifiable, Hashable {
    public let id: String
    public let title: String
    public let thumbnailURL: URL?
    public let fullImageURL: URL?

    public init(id: String, title: String, thumbnailURL: URL?, fullImageURL: URL?) {
        self.id = id
        self.title = title
        self.thumbnailURL = thumbnailURL
        self.fullImageURL = fullImageURL
    }

    public static func == (lhs: SearchResultItem, rhs: SearchResultItem) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
