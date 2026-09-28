import Foundation

public enum ImageSourceKind: String, CaseIterable, Identifiable {
    case ownImage = "Egen bild"
    // Egen flik istället för bara en knapp gömd under "Webb" - "Klistra
    // in" hörde egentligen inte ihop med webbsökningen (t.ex. en
    // skärmbild har inget med webben att göra), vilket kändes oväntat
    // att behöva klicka på "Webb" för att hitta (rapporterat 2026-09-26).
    case paste = "Urklipp"
    // "Webb/AI" - INTE bara "Webb" (döpt om 2026-09-28) - fliken
    // rymmer både riktig websökning (Google/Pinterest) OCH AI-bildgenerering
    // (ChatGPT), och bara "Webb" gav ingen ledtråd om AI-delen.
    case web = "Webb/AI"

    public var id: String { rawValue }

    /// Lokaliserad visningstext - INTE `rawValue` direkt (det förblir den
    /// stabila, svenska identifieraren/nyckeln), se `ContentView.searchBar`.
    public var label: String {
        let locale = AppLanguage.current.locale
        switch self {
        case .ownImage: return String(localized: "Egen bild", bundle: .module, locale: locale)
        case .paste: return String(localized: "Urklipp", bundle: .module, locale: locale)
        case .web: return String(localized: "Webb/AI", bundle: .module, locale: locale)
        }
    }
}
