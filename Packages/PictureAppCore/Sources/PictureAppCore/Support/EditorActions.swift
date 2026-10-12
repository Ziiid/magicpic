import SwiftUI

/// Åtgärder som huvudfönstret (`ContentView`) exponerar till appens
/// menyrad (Arkiv/Redigera) via `focusedSceneValue` - menykommandona ligger
/// i `App/macOS` men viewmodellen lever inuti `ContentView`, så åtgärderna
/// lämnas ut som en liten, plattformsoberoende värdetyp istället.
public struct EditorActions {
    public var openImage: () -> Void
    public var save: () -> Void
    public var undo: () -> Void
    public var redo: () -> Void
    public var canSave: Bool
    public var canUndo: Bool
    public var canRedo: Bool

    public init(
        openImage: @escaping () -> Void, save: @escaping () -> Void,
        undo: @escaping () -> Void, redo: @escaping () -> Void,
        canSave: Bool, canUndo: Bool, canRedo: Bool
    ) {
        self.openImage = openImage
        self.save = save
        self.undo = undo
        self.redo = redo
        self.canSave = canSave
        self.canUndo = canUndo
        self.canRedo = canRedo
    }
}

public struct EditorActionsKey: FocusedValueKey {
    public typealias Value = EditorActions
}

public extension FocusedValues {
    var editorActions: EditorActions? {
        get { self[EditorActionsKey.self] }
        set { self[EditorActionsKey.self] = newValue }
    }
}

/// Lokaliserade menytexter för app-targetens menyrad (`App/macOS`), som
/// ligger i en ANNAN modul och därför inte kan slå upp i paketets
/// String Catalog själv - samma mönster som `ExporterMessages`.
public enum MenuMessages {
    public static var openImage: String { L("Öppna bild…") }
    public static var save: String { L("Spara") }
    public static var undo: String { L("Ångra") }
    public static var redo: String { L("Gör om") }
}
