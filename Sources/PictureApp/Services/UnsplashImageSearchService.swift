import Foundation

/// Söker efter bilder på webben via Unsplash (unsplash.com/developers).
/// Kräver bara en "Access Key" (gratis, enkel registrering, ingen kreditkorts-
/// eller Cloud Console-uppsättning krävs).
struct UnsplashImageSearchService {
    struct SearchError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func search(query: String, accessKey: String) async throws -> [SearchResultItem] {
        guard !accessKey.isEmpty else {
            throw SearchError(message: "Ange en Unsplash Access Key i Inställningar (kugghjulet).")
        }

        var components = URLComponents(string: "https://api.unsplash.com/search/photos")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "per_page", value: "20"),
            URLQueryItem(name: "content_filter", value: "high")
        ]

        guard let url = components.url else {
            throw SearchError(message: "Ogiltig sökfråga.")
        }

        var request = URLRequest(url: url)
        request.setValue("Client-ID \(accessKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            throw SearchError(message: "Unsplash svarade med fel (\(http.statusCode)). Kontrollera Access Key.\n\(bodyText.prefix(200))")
        }

        let decoded = try JSONDecoder().decode(UnsplashSearchResponse.self, from: data)

        return decoded.results.map { photo in
            SearchResultItem(
                id: "web-\(photo.id)",
                title: photo.altDescription ?? photo.description ?? "Bild",
                thumbnailURL: URL(string: photo.urls.small),
                fullImageURL: URL(string: photo.urls.regular),
                localAsset: nil
            )
        }
    }
}

private struct UnsplashSearchResponse: Decodable {
    let results: [UnsplashPhoto]
}

private struct UnsplashPhoto: Decodable {
    let id: String
    let description: String?
    let altDescription: String?
    let urls: UnsplashURLs

    enum CodingKeys: String, CodingKey {
        case id, description, urls
        case altDescription = "alt_description"
    }
}

private struct UnsplashURLs: Decodable {
    let regular: String
    let small: String
}
