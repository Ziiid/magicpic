import SwiftUI
import CoreGraphics

/// Appens delade visuella identitet - används av `ToolbarChrome` för
/// "hero"-actionsen (den medvetna 20%-avvikelsen från annars Mac-/
/// iOS-native kontroller, se `ToolbarChrome.swift`) OCH som den ENDA
/// signalen för "aktivt/valt/primärt" var den än förekommer i appen
/// (valda filter, valt motiv i motivväljaren, drop-target-highlight,
/// vald bakgrundsfärg) - se filens `accentCGColor` för varför.
///
/// Samma stil på BÅDA plattformarna - INGET `#if os(macOS)` här. En
/// pill-formad, accentfärgad knapp för de viktigaste actionsen (Bakgrund,
/// Finjustera, Spara/Dela) fungerar lika bra som tydlig call-to-action på
/// iPhone/iPad som på Mac.
///
/// Färgen är Doxtail-grön (`#6aab8a`, salvia-grön) - SAMMA gröna som
/// redan används genomgående i systerapparna (Dogsona/dog-id/Dogish/
/// Persona/doxtail-web, dokumenterat som "Primär (salvia-grön)" i deras
/// egna CLAUDE.md/AGENTS.md) - INTE en egen, ny färg uppfunnen bara för
/// den här appen. Medvetet INTE `Color.accentColor` (systemets egen
/// accentfärg, som kan vara vad som helst beroende på användarens egna
/// macOS-inställningar) - `Color.accentColor` ska INTE längre användas
/// någonstans i appen (se `buggs.md`/`CLAUDE.md`), exakt av det skälet:
/// den skulle göra "aktivt/valt" inkonsekvent mellan olika användares
/// datorer, och inkonsekvent med resten av Doxtail-produktfamiljen.
public enum AppTheme {
    // #6aab8a, uträknat explicit som Double (INTE `0x6a / 255`, som
    // riskerar heltalsdivision om typinferensen någonsin skulle luta åt
    // Int i ett annat sammanhang) - lätt att verifiera mot hex-koden
    // ovan.
    private static let accentRed = Double(0x6a) / 255.0
    private static let accentGreen = Double(0xab) / 255.0
    private static let accentBlue = Double(0x8a) / 255.0

    public static let accent = Color(red: accentRed, green: accentGreen, blue: accentBlue)

    /// Samma färg som `accent`, som `CGColor` - för de ställen som jobbar
    /// med CoreImage/CoreGraphics direkt (t.ex. motivväljarens
    /// overlay-rendering i `SearchViewModel`) istället för SwiftUI `Color`.
    /// `CGColor` vill ha `CGFloat`, inte `Double` (de konverterar INTE
    /// implicit mellan varandra i Swift) - därav de uttryckliga `CGFloat(...)`.
    public static let accentCGColor = CGColor(red: CGFloat(accentRed), green: CGFloat(accentGreen), blue: CGFloat(accentBlue), alpha: 1)

    private static let onAccentRed = Double(0xfa) / 255.0
    private static let onAccentGreen = Double(0xf9) / 255.0
    private static let onAccentBlue = Double(0xf7) / 255.0

    /// Off-white (samma varma ton som systerapparnas `#faf9f7`, inte rent
    /// vitt) - text/ikonfärg OVANPÅ `accent` (hero-knapparnas fyllning).
    public static let onAccent = Color(red: onAccentRed, green: onAccentGreen, blue: onAccentBlue)

    /// Samma varma off-white som `onAccent`, som `CGColor` - för Polaroid-/
    /// fotoautomat-ramarna i `PhotoFilterService` (ren CoreImage-komposition,
    /// jobbar med `CGColor`/`CIColor`, inte SwiftUI `Color`). Återanvänder
    /// den redan etablerade tonen istället för att hitta på en ny vit/
    /// off-white nyans bara för ramarna.
    public static let onAccentCGColor = CGColor(red: CGFloat(onAccentRed), green: CGFloat(onAccentGreen), blue: CGFloat(onAccentBlue), alpha: 1)
}
