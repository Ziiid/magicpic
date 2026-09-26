import SwiftUI

/// Den delade visuella "80/20"-principen för verktygsradens kontroller (se
/// designmockupen som låg till grund för det här): de flesta kontrollerna
/// (`.native`) ska kännas som vanliga, obetonade Mac-/iOS-knappar - en tunn
/// kontur, ingen fyllning, diskret hover/tryck-respons. Ett fåtal
/// nyckel-actions (`.hero`: BARA Bakgrund och Spara/Dela - appens egna
/// kärnlöfte, "ta bort/byta bakgrund... och spara resultatet" per
/// `CLAUDE.md`s enderadsbeskrivning, se motiveringen vid `backgroundMenu`
/// i `DetailPanel.swift`) får istället en egen, mer designad känsla -
/// rundad pill i appens accentfärg (`AppTheme.accent`), mjuk skugga/glöd,
/// en lätt lyft-känsla vid hover.
///
/// Delad mellan vanliga `Button`er (via `NativeToolbarButtonStyle` nedan,
/// som bara skickar `configuration.label` genom den här vyn) OCH
/// `Menu`-etiketter (som INTE är knappar och därför inte kan använda
/// `.buttonStyle(_:)` - `backgroundMenu` i `DetailPanel` använder
/// `ToolbarChrome` direkt som sitt `label:`-innehåll istället) - annars
/// hade den visuella "receptet" behövt underhållas på två ställen.
///
/// Hover byggs med `.onHover` (fungerar på Mac via mus/styrplatta OCH på
/// iPad med Pointer-stöd - fungerar bara aldrig med rent touch, vilket är
/// korrekt: det finns inget "hover" där) - samma mönster som projektets
/// övriga delade gester (se `ManipulableImageView`), en gång för båda
/// plattformarna istället för `#if os(macOS)`.
public struct ToolbarChrome<Content: View>: View {
    public enum Tier {
        case native
        case hero
    }

    private let tier: Tier
    private let isPressed: Bool
    private let content: Content

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    public init(tier: Tier, isPressed: Bool = false, @ViewBuilder content: () -> Content) {
        self.tier = tier
        self.isPressed = isPressed
        self.content = content()
    }

    public var body: some View {
        switch tier {
        case .native:
            content
                .font(.callout.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(nativeFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }

        case .hero:
            content
                .font(.callout.weight(.semibold))
                .foregroundStyle(AppTheme.onAccent)
                .padding(.horizontal, 15)
                .padding(.vertical, 7)
                .background(
                    Capsule(style: .continuous).fill(AppTheme.accent)
                )
                .brightness(isPressed ? -0.06 : (isHovering ? 0.05 : 0))
                .shadow(
                    color: AppTheme.accent.opacity(isHovering ? 0.45 : 0.3),
                    radius: isHovering ? 10 : 6,
                    y: isHovering ? 3 : 2
                )
                .scaleEffect(isPressed ? 0.97 : (isHovering ? 1.02 : 1))
                .offset(y: (isHovering && !isPressed) ? -1 : 0)
                .opacity(isEnabled ? 1 : 0.5)
                .contentShape(Capsule())
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.15), value: isHovering)
                .animation(.easeOut(duration: 0.12), value: isPressed)
        }
    }

    private var nativeFill: Color {
        if isPressed { return Color.primary.opacity(0.12) }
        if isHovering { return Color.primary.opacity(0.06) }
        return .clear
    }
}

/// Den nativa (80%) `ButtonStyle`n - Ångra/Gör om/Återställ, Filter,
/// Justera, Motiv, Finjustera - alla verktyg utom Bakgrund/Exportera
/// (de enda två hero-kontrollerna, se `DetailPanel.backgroundMenu`s
/// motivering).
public struct NativeToolbarButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        ToolbarChrome(tier: .native, isPressed: configuration.isPressed) {
            configuration.label
        }
    }
}

public extension ButtonStyle where Self == NativeToolbarButtonStyle {
    static var nativeToolbar: NativeToolbarButtonStyle { NativeToolbarButtonStyle() }
}

// Ingen `HeroButtonStyle`/`.heroToolbar` för fristående `Button`er - de
// enda två hero-kontrollerna (Bakgrund, Exportera) är en `Menu`-etikett
// respektive ett segmenterat kluster (`HeroSegmentButtonStyle` nedan),
// ingen av dem en vanlig `Button` som skulle behöva en sådan stil. Togs
// bort 2026-09-26 (fanns tidigare för Finjustera, som flyttades till
// native, se `backgroundMenu`s motivering) istället för att lämnas kvar
// oanvänd - lägg tillbaka den (`ToolbarChrome(tier: .hero, isPressed:)`
// via `ButtonStyle`, som `NativeToolbarButtonStyle` ovan) om en fristående
// hero-knapp faktiskt behövs igen.

/// Ett enskilt segment INUTI en redan hero-färgad pill (t.ex. Spara/Dela-
/// klustret i `DetailPanel`) - bara en diskret vit hover-/tryck-tvätt, ingen
/// egen bakgrund/skugga (den kommer från den omslutande pillens `.hero`-
/// `ToolbarChrome` istället), annars skulle varje segment fått sin EGEN
/// pill-form och sköna helheten.
public struct HeroSegmentButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HeroSegmentBody(configuration: configuration)
    }
}

private struct HeroSegmentBody: View {
    let configuration: HeroSegmentButtonStyle.Configuration
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .background(
                Capsule(style: .continuous).fill(wash)
            )
            .opacity(isEnabled ? 1 : 0.5)
            .onHover { isHovering = $0 }
    }

    private var wash: Color {
        if configuration.isPressed { return AppTheme.onAccent.opacity(0.28) }
        if isHovering { return AppTheme.onAccent.opacity(0.16) }
        return .clear
    }
}

public extension ButtonStyle where Self == HeroSegmentButtonStyle {
    static var heroSegment: HeroSegmentButtonStyle { HeroSegmentButtonStyle() }
}
