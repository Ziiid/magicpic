import Foundation

public enum ImageSourceKind: String, CaseIterable, Identifiable {
    case web = "Webb"
    case ownImage = "Egen bild"

    public var id: String { rawValue }
}
