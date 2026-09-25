import Foundation

/// Identifierar en bild som laddats in i appen (importerad fil, Foton,
/// kamera, eller indragen från en webbläsare) - används för att visa
/// ett namn och avgöra om en bild är vald (`SearchViewModel.selectedItem`).
public struct SearchResultItem: Identifiable, Hashable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    public static func == (lhs: SearchResultItem, rhs: SearchResultItem) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
