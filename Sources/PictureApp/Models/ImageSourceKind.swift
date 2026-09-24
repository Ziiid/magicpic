import Foundation

enum ImageSourceKind: String, CaseIterable, Identifiable {
    case web = "Webb"
    case photos = "Foton"

    var id: String { rawValue }
}
