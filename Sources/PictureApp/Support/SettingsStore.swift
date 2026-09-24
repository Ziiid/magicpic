import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @Published var unsplashAccessKey: String {
        didSet { KeychainHelper.save(unsplashAccessKey, for: "unsplashAccessKey") }
    }

    init() {
        unsplashAccessKey = KeychainHelper.load(for: "unsplashAccessKey") ?? ""
    }
}
