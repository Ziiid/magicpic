import Foundation

/// Kort hjälpfunktion för att lokalisera en bokstavlig sträng mot
/// `Localizable.xcstrings` - används istället för att lita på SwiftUIs
/// "automatiska" bundle-upptäckt för vanliga `Text("...")`/`Button("...")`/
/// `.help("...")`-anrop, vilket VISADE SIG INTE fungera i praktiken
/// (bekräftat 2026-09-28 av användaren - flik-namn som gick via
/// `String(localized:bundle:.module,...)` översattes korrekt, men vanliga
/// `Text`/`Toggle`/`Button`-literaler gjorde det INTE, trots
/// `.environment(\.locale, ...)` på `ContentView`s rot). `bundle: .module`
/// MÅSTE alltså anges explicit - `L(...)` är bara en kortare stavning av
/// det redan beprövade mönstret.
public func L(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module, locale: AppLanguage.current.locale)
}
