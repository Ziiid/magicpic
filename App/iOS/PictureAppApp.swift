import SwiftUI
import PictureAppCore

@main
struct PictureAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(exporter: IOSImageExporter())
        }
    }
}
