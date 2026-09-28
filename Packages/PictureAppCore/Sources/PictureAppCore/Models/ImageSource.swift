import Foundation

/// Vald källa i "Källa"-väljaren i sökfältet - antingen en hårdkodad
/// sökmotor (`WebSearchEngine`) eller en användardefinierad AI-
/// bildgenerator (`AIImageGenerator`, tillagd i Inställningar). Slår ihop
/// dem till EN typ så `SearchViewModel.searchEngine`/`ContentView`s
/// "Källa"-`Picker` kan hantera båda likadant.
public enum ImageSource: Hashable, Identifiable {
    case engine(WebSearchEngine)
    case generator(AIImageGenerator)

    public var id: String {
        switch self {
        case .engine(let engine): return "engine:\(engine.rawValue)"
        case .generator(let generator): return "generator:\(generator.id.uuidString)"
        }
    }

    public var label: String {
        switch self {
        case .engine(let engine): return engine.rawValue
        case .generator(let generator): return generator.name
        }
    }

    /// Sant för en AI-bildgenerator, falskt för en riktig sökmotor - styr
    /// t.ex. om "Klistra in bild"-knappen/instruktionstexten för AI-
    /// generering visas i `ContentView` (vi vet inte om en
    /// användartillagd sida stödjer drag, så samma säkra "klistra in"-
    /// fallback som tidigare gällde hårdkodat bara för ChatGPT gäller nu
    /// alla AI-generatorer).
    public var isGenerator: Bool {
        if case .generator = self { return true }
        return false
    }

    public func url(for query: String) -> URL? {
        switch self {
        case .engine(let engine): return engine.searchURL(for: query)
        case .generator(let generator): return generator.promptURL(for: query)
        }
    }
}
