import Foundation

/// Lokaliserar en sträng mot `Localizable.xcstrings` på APPENS valda språk
/// (`AppLanguage.current`), helt oberoende av enhetens systemspråk.
///
/// Slår UPP MOT RÄTT SPRÅKS EGEN `.lproj` (`AppLanguage.bundle`) istället för
/// att lita på `String(localized:locale:)`s `locale`-parameter - den väljer
/// inte pålitligt språk (den styr främst formatering) och föll tillbaka på
/// enhetens språk, så språkväxeln i Inställningar gav fel/blandat språk
/// (rapporterat 2026-10-14).
///
/// Svenska är KÄLLSPRÅKET: nyckeln ÄR den svenska texten. Slår man upp den
/// mot en tabell som inte finns returnerar `String(localized:)` nyckeln
/// oförändrad (med interpolation utförd) - exakt den svenska texten, utan
/// att något språk i bundeln kan "lysa igenom".
public func L(_ key: String.LocalizationValue) -> String {
    switch AppLanguage.current {
    case .swedish:
        return String(
            localized: key,
            table: "__svenska_kalltext__",
            bundle: .module,
            locale: AppLanguage.swedish.locale
        )
    case .english:
        return String(localized: key, bundle: AppLanguage.english.bundle, locale: AppLanguage.english.locale)
    }
}
