import SwiftUI

/// Formväljare med RIKTIGA förhandsgranskningar (bilden faktiskt beskuren
/// till varje preset) - samma mönster som `PhotoFilterPickerView`, tidigare
/// saknat här (formvalet var bara en textmeny med en generisk ikon per
/// form, rapporterat 2026-09-26).
///
/// Visar `ShapePreset.all` - praktiska genvägar ("LinkedIn-profil",
/// "Instagram-inlägg" osv., fast bildförhållande OCH pixelmått) följt av
/// de generiska geometriska formerna (fri storlek, oförändrat beteende) -
/// se `ShapePreset`s dokumentation. Namnet är den PRIMÄRA informationen i
/// varje ruta, den tekniska detaljen (bildförhållande · pixelmått) en
/// diskret undertext - användaren ska kunna tänka "jag behöver en
/// LinkedIn-profilbild" istället för att behöva veta att det innebär 1:1.
///
/// Miniatyrerna visar ALLTID en centrerad beskärning (`.identity`), inte
/// användarens nuvarande pan/zoom - den är inställd för en annan kanvas och
/// gav förskjutna/förminskade, delvis genomskinliga rutor i andra former.
///
/// Miniatyrerna genereras EN gång från en nedskalad kopia av bilden
/// (`PlatformImage.resized(maxDimension:)`) - till skillnad från
/// `BackgroundStylePickerView` finns ingen mask att hålla i synk med, så
/// nedskalning FÖRE beskärning är säkert här (`ShapeCropService` skapar
/// sin egen formmask i exakt den storlek den beskurna bilden råkar ha).
struct ShapePickerView: View {
    let baseImage: PlatformImage
    let transform: CanvasTransform
    let currentPreset: ShapePreset
    // Polaroid/Fotoautomat vald - formen syns då inte i förhandsvisningen.
    let isLayoutFilterActive: Bool
    let onSelect: (ShapePreset) -> Void
    let onDone: () -> Void

    // Nyckeln är `preset.id`, INTE konturen (`OutputShape`) - flera
    // praktiska presets delar samma `.square`-kontur (t.ex. LinkedIn-profil
    // och Instagram-inlägg) och skulle annars skriva över varandras
    // miniatyr i dictionaryt.
    @State private var thumbnails: [String: PlatformImage] = [:]

    var body: some View {
        VStack(spacing: 16) {
            Text(L("Form"))
                .font(.headline)

            if isLayoutFilterActive {
                Label(L("Polaroid och Fotoautomat bygger sin egen ram, så form och position kan inte ändras medan de är valda. Välj Ingen eller ett annat filter för att ändra dem."), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 16) {
                    ForEach(ShapePreset.all) { preset in
                        Button {
                            onSelect(preset)
                        } label: {
                            VStack(spacing: 6) {
                                thumbnailView(for: preset)
                                    .frame(width: thumbnailSize(for: preset).width, height: thumbnailSize(for: preset).height)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(preset.id == currentPreset.id ? AppTheme.accent : Color.secondary.opacity(0.2), lineWidth: preset.id == currentPreset.id ? 3 : 1)
                                    )
                                    .frame(height: 84, alignment: .bottom)

                                VStack(spacing: 1) {
                                    Text(preset.name)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                    if let subtitle = preset.subtitle {
                                        Text(subtitle)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.75)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }

            HStack {
                Spacer()
                Button(L("Klart")) { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 460, minHeight: 460, idealHeight: 560)
        .task { await generateThumbnails() }
    }

    /// Miniatyrens EGNA ram - "fit" inom en 84×84-box efter `preset`s
    /// bildförhållande, så t.ex. en smal/hög Instagram Story-ruta faktiskt
    /// SER smal/hög ut bredvid en bred YouTube-miniatyr-ruta, istället för
    /// att alla tvingas in i samma fasta kvadrat och skillnaden bara syns i
    /// texten. Rektangel (inget fast bildförhållande) faller tillbaka på
    /// en kvadratisk box, precis som tidigare.
    private func thumbnailSize(for preset: ShapePreset) -> CGSize {
        let aspect = preset.aspectRatio ?? 1
        let maxDimension: CGFloat = 84
        return aspect >= 1
            ? CGSize(width: maxDimension, height: maxDimension / aspect)
            : CGSize(width: maxDimension * aspect, height: maxDimension)
    }

    @ViewBuilder
    private func thumbnailView(for preset: ShapePreset) -> some View {
        if let thumbnail = thumbnails[preset.id] {
            ZStack {
                CheckerboardBackground()
                Image(platformImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .overlay(ProgressView().controlSize(.small))
        }
    }

    private func generateThumbnails() async {
        let shapeCrop = ShapeCropService()
        let small = baseImage.resized(maxDimension: 160)
        for preset in ShapePreset.all {
            guard let result = try? shapeCrop.apply(preset, to: small) else { continue }
            thumbnails[preset.id] = result
        }
    }
}
