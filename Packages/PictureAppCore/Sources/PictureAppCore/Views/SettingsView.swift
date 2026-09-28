import SwiftUI

/// Appens inställningar - mörkt läge och språk, öppnas via kugghjulet i
/// sökfältet (`ContentView`). Egen liten vy istället för en meny/popover
/// eftersom fler inställningar kan tillkomma här.
struct SettingsView: View {
    @Binding var useDarkMode: Bool
    @Binding var appLanguage: AppLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Toggle(L("Mörkt läge"), isOn: $useDarkMode)

                Picker(L("Språk"), selection: $appLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }
                .pickerStyle(.segmented)
            }
            .navigationTitle(L("Inställningar"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Klart")) { dismiss() }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 200)
    }
}
