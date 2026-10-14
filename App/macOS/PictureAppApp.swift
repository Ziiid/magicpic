import SwiftUI
import PictureAppCore

@main
struct PictureAppApp: App {
    // Åtgärderna i det fokuserade fönstret (`ContentView` exponerar dem via
    // `focusedSceneValue`) - menyraden ligger här men viewmodellen inuti vyn.
    @FocusedValue(\.editorActions) private var actions
    // Läses bara för att menyraden ska byggas om (MenuMessages) när
    // appens språk byts i Inställningar.
    @AppStorage("appLanguage") private var appLanguage = "en"

    var body: some Scene {
        WindowGroup {
            ContentView(exporter: MacImageExporter())
                .frame(minWidth: 900, minHeight: 600)
        }
        // Rymligare standardfönster - minsta storleken (900 × 600) är
        // trångt för tomtillståndet. Gäller bara nya fönster; ett redan
        // sparat fönster behåller sin storlek.
        .defaultSize(width: 1100, height: 780)
        .commands {
            let _ = appLanguage
            CommandGroup(after: .newItem) {
                Button(MenuMessages.openImage) { actions?.openImage() }
                    .keyboardShortcut("o")
                    .disabled(actions == nil)
            }
            CommandGroup(replacing: .saveItem) {
                Button(MenuMessages.save) { actions?.save() }
                    .keyboardShortcut("s")
                    .disabled(!(actions?.canSave ?? false))
            }
            CommandGroup(replacing: .undoRedo) {
                Button(MenuMessages.undo) { actions?.undo() }
                    .keyboardShortcut("z")
                    .disabled(!(actions?.canUndo ?? false))
                Button(MenuMessages.redo) { actions?.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!(actions?.canRedo ?? false))
            }
        }
    }
}
