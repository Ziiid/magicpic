import Foundation

public enum ImageSourceKind: String, CaseIterable, Identifiable {
    case web = "Webb"
    case ownImage = "Egen bild"
    // Egen flik istället för bara en knapp gömd under "Webb" - "Klistra
    // in" hörde egentligen inte ihop med webbsökningen (t.ex. en
    // skärmbild har inget med webben att göra), vilket kändes oväntat
    // att behöva klicka på "Webb" för att hitta (rapporterat 2026-09-26).
    case paste = "Urklipp"

    public var id: String { rawValue }
}
