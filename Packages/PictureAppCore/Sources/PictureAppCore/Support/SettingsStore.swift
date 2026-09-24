import SwiftUI

@MainActor
public final class SettingsStore: ObservableObject {
    @Published public var unsplashAccessKey: String {
        didSet { KeychainHelper.save(unsplashAccessKey, for: "unsplashAccessKey") }
    }

    public init() {
        unsplashAccessKey = KeychainHelper.load(for: "unsplashAccessKey") ?? ""
    }
}
