import SwiftUI

/// Appens inställningar - mörkt läge, språk och användarens egna AI-
/// bildgeneratorer - öppnas via kugghjulet i sökfältet (`ContentView`).
/// Egen liten vy istället för en meny/popover eftersom fler inställningar
/// kan tillkomma här.
struct SettingsView: View {
    @Binding var useDarkMode: Bool
    @Binding var appLanguage: AppLanguage
    @Binding var generators: AIImageGeneratorList
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var newURL = ""

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

                Section(L("AI-bildgeneratorer")) {
                    ForEach(generators.items) { generator in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(generator.name)
                            Text(generator.urlString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { indexSet in
                        generators.items.remove(atOffsets: indexSet)
                    }

                    TextField(L("Namn (t.ex. GPT Image)"), text: $newName)
                    TextField(L("Url (t.ex. chatgpt.com)"), text: $newURL)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()

                    Button(L("Lägg till")) {
                        addGenerator()
                    }
                    .disabled(
                        newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
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
        .frame(minWidth: 360, minHeight: 320)
    }

    private func addGenerator() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !url.isEmpty else { return }
        generators.items.append(AIImageGenerator(name: name, urlString: url))
        newName = ""
        newURL = ""
    }
}
