import SwiftUI

/// Ett förval: ett tryck sätter bakgrund, form och effekter på en gång, så
/// man slipper gå igenom menyerna en och en. Bara en lista med redan
/// befintliga inställningar (`BackgroundOption`, `ShapePreset`,
/// `SubjectEffects`) - inga nya begrepp. Texterna slås upp PER ANROP (inte
/// lagrade) så de följer språkväxlingen, se `ShapePreset.name`.
public struct QuickPreset: Identifiable {
    public let id: String
    public let systemImage: String
    let backgroundStyle: BackgroundOption
    /// `ShapePreset.id` (se `ShapePreset.all`).
    let shapeID: String
    let effects: SubjectEffects

    public var name: String {
        switch id {
        case "product": return L("Produktbild")
        case "profile": return L("Profilbild")
        case "instagram": return L("Instagram-inlägg")
        default: return L("Klistermärke")
        }
    }

    public var detail: String {
        switch id {
        case "product": return L("Vit bakgrund, kvadrat 1000 × 1000 och en mjuk skugga.")
        case "profile": return L("Rund bild 800 × 800 mot en mjuk gradient.")
        case "instagram": return L("4:5 (1080 × 1350) med oskarp bakgrund.")
        default: return L("Genomskinlig bakgrund med vit kant och skugga.")
        }
    }

    static let gradient = GradientPreset.all.first { $0.id == "sky" } ?? GradientPreset.all[0]

    public static let all: [QuickPreset] = [
        QuickPreset(
            id: "product", systemImage: "shippingbox",
            backgroundStyle: .color(.white), shapeID: "cvSquare",
            effects: SubjectEffects(shadow: 0.4)
        ),
        QuickPreset(
            id: "profile", systemImage: "person.crop.circle",
            backgroundStyle: .gradient(gradient), shapeID: "avatarCircle",
            effects: .none
        ),
        QuickPreset(
            id: "instagram", systemImage: "camera.aperture",
            backgroundStyle: .blurredOriginal, shapeID: "instagramPost",
            effects: .none
        ),
        QuickPreset(
            id: "sticker", systemImage: "seal",
            backgroundStyle: .transparent, shapeID: "square",
            effects: SubjectEffects(shadow: 0.3, outlineWidth: 0.35, outlineColor: .white)
        ),
    ]
}
