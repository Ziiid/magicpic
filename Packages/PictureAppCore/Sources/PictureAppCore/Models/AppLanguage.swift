import Foundation

/// Appens EGET språkval, oberoende av enhetens systemspråk - växlas i
/// Inställningar (`SettingsView`), sparas via `@AppStorage("appLanguage")`
/// i `ContentView` (samma UserDefaults-nyckel som `current` nedan läser,
/// så de alltid är i synk).
///
/// Default är ENGELSKA, inte svenska - appens eget namn (XtraPic) och
/// filterstilarnas namn (Process, Tonal, Vignette...) är redan engelska/
/// internationella, och App Store-distribution är global - en
/// förstagångsanvändare ska mötas av engelska, med svenska som ett lätt
/// tillgängligt alternativ, inte tvärtom.
public enum AppLanguage: String, CaseIterable, Identifiable {
    case swedish = "sv"
    case english = "en"

    public var id: String { rawValue }

    public var locale: Locale { Locale(identifier: rawValue) }

    public var label: String {
        switch self {
        case .swedish: return "Svenska"
        case .english: return "English"
        }
    }

    /// Läses direkt ur UserDefaults - för kod UTAN tillgång till SwiftUI-
    /// miljön (modeller/services, t.ex. `PhotoFilter.label`), som inte kan
    /// läsa `@AppStorage`/`.environment(\.locale)` men ändå behöver veta
    /// vilket språk användaren valt just nu.
    public static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .english
    }
}
