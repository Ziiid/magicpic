import Foundation

public enum ImageSourceKind: String, CaseIterable, Identifiable {
    case ownImage = "Egen bild"
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
        case .ownImage: return L("Egen bild")
        case .web: return L("Webb/AI")
        }
    }
}
