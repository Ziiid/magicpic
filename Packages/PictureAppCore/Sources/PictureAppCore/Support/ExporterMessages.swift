import Foundation

/// Lokaliserade felmeddelanden för `MacImageExporter`/`IOSImageExporter`
/// (i `App/macOS`/`App/iOS`, ANDRA moduler än `PictureAppCore`) - de kan
/// inte lokalisera sina egna literaler med `bundle: .module` (det skulle
/// peka på FEL modul/katalog), så de anropar de här delade,
/// PictureAppCore-lokaliserade egenskaperna istället.
public enum ExporterMessages {
    public static var couldNotCreateImageData: String {
        L("Kunde inte skapa bilddata.")
    }

    public static var photosPermissionDenied: String {
        L("XtraPic saknar behörighet att spara i Foton.")
    }
}
