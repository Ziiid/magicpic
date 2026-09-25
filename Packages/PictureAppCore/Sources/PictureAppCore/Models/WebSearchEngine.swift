import Foundation

/// En webbkälla att öppna i systemets webbläsare för att hitta eller
/// SKAPA en bild - antingen en riktig sökmotor (Google/Pinterest) eller
/// en AI-bildgenerator (ChatGPT). Ingen egen bildhämtning i appen (som
/// tidigare med Unsplash) - istället länkas källan med användarens
/// sökterm/prompt, helt utan API-nyckel. Bilden man hittar/skapar dras
/// sedan in i appen precis som vilken webbild/fil som helst -
/// `ContentView`s `.onDrop` hanterar redan fjärr-URL:er och rå bilddata,
/// inte bara lokala filer.
public enum WebSearchEngine: String, CaseIterable, Identifiable {
    case google = "Google"
    case pinterest = "Pinterest"
    case chatGPT = "ChatGPT"

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
        case .chatGPT:
            // chatgpt.com förifyller meddelanderutan med `q`-parametern
            // (inofficiellt men väldokumenterat/stabilt beteende, samma
            // sorts URL-genväg som Google/Pinterest ovan - fortfarande
            // ingen API-nyckel, bara en vanlig länk användaren själv
            // öppnar i sin egen inloggade session). Prefixar prompten så
            // ChatGPT tolkar det som en bildgenereringsförfrågan istället
            // för en vanlig fråga.
            components = URLComponents(string: "https://chatgpt.com/")!
            components.queryItems = [URLQueryItem(name: "q", value: "Skapa en bild: \(query)")]
        }
        return components.url
    }
}
