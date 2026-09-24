import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Unsplash-sökinställningar")
                .font(.headline)

            Text("Skapa ett gratis konto på unsplash.com/developers, skapa en app och kopiera dess \"Access Key\". Ingen betalning eller Cloud Console krävs.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Access Key")
                SecureField("Unsplash Access Key", text: $settings.unsplashAccessKey)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Klart") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        #if os(macOS)
        .frame(width: 440)
        #else
        .frame(maxWidth: 440)
        #endif
    }
}
