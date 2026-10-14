import Foundation

/// En användardefinierad AI-bildgenerator (t.ex. "GPT Image", "Midjourney",
/// "Gemini") - läggs till/tas bort i Inställningar (`SettingsView`) istället
/// för att vara hårdkodad i appen, eftersom vilken tjänst som är populärast
/// skiftar snabbt. Till skillnad från `WebSearchEngine` (Google/Pinterest,
/// som har en stabil, hårdkodad sök-URL) har varje generator bara ett namn
/// och en bas-URL - samma `q`-parameter-mönster som tidigare användes
/// hårdkodat för `chatgpt.com` används generiskt här.
public struct AIImageGenerator: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var urlString: String

    public init(id: UUID = UUID(), name: String, urlString: String) {
        self.id = id
        self.name = name
        self.urlString = urlString
    }

    /// Bygger URL:en att öppna i systemets webbläsare för en given prompt -
    /// lägger till/uppdaterar `q`-frågeparametern på `urlString`, precis som
    /// det tidigare hårdkodade chatgpt.com-specialfallet (`chatgpt.com`
    /// förifyller meddelanderutan med `q`, ett vanligt, om än inofficiellt,
    /// mönster hos flera AI-chattsidor). Lägger till `https://` om
    /// användaren bara skrivit t.ex. "chatgpt.com" utan schema.
    public func promptURL(for query: String) -> URL? {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains("://") {
            trimmed = "https://\(trimmed)"
        }
        guard var components = URLComponents(string: trimmed) else { return nil }
        let prefix = L("Skapa en bild:")
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "q", value: "\(prefix) \(query)"))
        components.queryItems = items
        return components.url
    }
}

/// `@AppStorage`-vänlig wrapper runt listan av sparade generatorer - kodas
/// till/från en JSON-sträng eftersom `@AppStorage` bara stödjer
/// `RawRepresentable`-typer med `RawValue == String` direkt, inte en array
/// av `Codable`-structar (samma mönster som `AppLanguage`, fast för en
/// array istället för en enkel enum).
public struct AIImageGeneratorList: RawRepresentable, Equatable {
    public var items: [AIImageGenerator]

    public init(items: [AIImageGenerator] = []) {
        self.items = items
    }

    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let items = try? JSONDecoder().decode([AIImageGenerator].self, from: data) else {
            self.items = []
            return
        }
        self.items = items
    }

    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(items),
              let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }
}
