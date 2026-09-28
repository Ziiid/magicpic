import Foundation

/// En riktig sökmotor att öppna i systemets webbläsare för att HITTA en
/// bild - Google/Pinterest, med en stabil, hårdkodad sök-URL (till
/// skillnad från AI-bildgeneratorer, se `AIImageGenerator`, vars URL är
/// användardefinierad i Inställningar eftersom vilken tjänst som är
/// populärast skiftar snabbt). Ingen egen bildhämtning i appen (som
/// tidigare med Unsplash) - istället länkas källan med användarens
/// sökterm, helt utan API-nyckel. Bilden man hittar dras sedan in i appen
/// precis som vilken webbild/fil som helst - `ContentView`s `.onDrop`
/// hanterar redan fjärr-URL:er och rå bilddata, inte bara lokala filer.
public enum WebSearchEngine: String, CaseIterable, Identifiable {
    case google = "Google"
    case pinterest = "Pinterest"

    public var id: String { rawValue }

    public func searchURL(for query: String) -> URL? {
        var components: URLComponents
        switch self {
        case .google:
            components = URLComponents(string: "https://www.google.com/search")!
            components.queryItems = [
                URLQueryItem(name: "tbm", value: "isch"),
                URLQueryItem(name: "q", value: query),
            ]
        case .pinterest:
            components = URLComponents(string: "https://www.pinterest.com/search/pins/")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
        }
        return components.url
    }
}
