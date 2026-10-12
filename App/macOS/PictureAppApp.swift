import SwiftUI
import PictureAppCore

@main
struct PictureAppApp: App {
    // Åtgärderna i det fokuserade fönstret (`ContentView` exponerar dem via
    // `focusedSceneValue`) - menyraden ligger här men viewmodellen inuti vyn.
    @FocusedValue(\.editorActions) private var actions

    var body: some Scene {
        WindowGroup {
            ContentView(exporter: MacImageExporter())
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
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
