import SwiftUI
import PictureAppCore

@main
struct PictureAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(exporter: MacImageExporter())
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
