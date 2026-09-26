import SwiftUI

/// Bakgrundsväljare med RIKTIGA förhandsgranskningar (motivet kompositerat
/// mot varje alternativ) - samma mönster som `PhotoFilterPickerView`,
/// tidigare saknat här (bakgrundsvalet var bara en textmeny, rapporterat
/// 2026-09-26).
///
/// Bara de "enkla" valen (genomskinlig, oskärpa, förvalda färger) visas som
/// riktiga miniatyrer i rutnätet - "Egen bild…" (öppnar filväljaren) och
/// "Justera position…" (bara relevant när en egen bild redan är vald) är
/// inte EN av flera fasta förhandsvisningar utan öppnar egna flöden, och
/// ligger därför som vanliga knappar under rutnätet istället.
struct BackgroundStylePickerView: View {
    let baseImage: PlatformImage
    let currentStyle: BackgroundOption
    let hasCustomBackground: Bool
    let onSelect: (BackgroundOption) -> Void
    let onPickCustomImage: () -> Void
    let onRepositionCustomImage: () -> Void
    let onPickMoreColors: () -> Void
    let onDone: () -> Void
    let loadPreviewMask: () async -> BackgroundRemovalService.ForegroundMask?

    @State private var thumbnails: [OptionKey: PlatformImage] = [:]
    @State private var didFailToLoadMask = false

    private enum OptionKey: Hashable {
        case transparent
        case blurred
        case color(Color)
    }

    private struct Option {
        let key: OptionKey
        let style: BackgroundOption
        let label: String?
    }

    private var options: [Option] {
        var result = [
            Option(key: .transparent, style: .transparent, label: "Ingen"),
            Option(key: .blurred, style: .blurredOriginal, label: "Oskärpa"),
        ]
        for color in BackgroundOption.presetColors {
            result.append(Option(key: .color(color), style: .color(color), label: nil))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Bakgrund")
                .font(.headline)

            if didFailToLoadMask {
                Text("Kunde inte analysera bilden för förhandsvisning. Prova igen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 12)], spacing: 16) {
                    ForEach(options, id: \.key) { option in
                        Button {
                            onSelect(option.style)
                        } label: {
                            VStack(spacing: 6) {
                                thumbnailView(for: option.key)
                                    .frame(width: 68, height: 68)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(option.style == currentStyle ? AppTheme.accent : Color.secondary.opacity(0.2), lineWidth: option.style == currentStyle ? 3 : 1)
                                    )
                                if let label = option.label {
                                    Text(label)
                                        .font(.caption2)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
            }

            VStack(spacing: 8) {
                Button {
                    onPickMoreColors()
                } label: {
                    Label("Fler färger…", systemImage: "paintpalette")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.nativeToolbar)

                Button {
                    onPickCustomImage()
                } label: {
                    Label("Egen bild…", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.nativeToolbar)

                if hasCustomBackground {
                    Button {
                        onRepositionCustomImage()
                    } label: {
                        Label("Justera position…", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.nativeToolbar)
                }
            }

            HStack {
                Spacer()
                Button("Klart") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 440, minHeight: 460, idealHeight: 560)
        .task { await generateThumbnails() }
    }

    @ViewBuilder
    private func thumbnailView(for key: OptionKey) -> some View {
        if let thumbnail = thumbnails[key] {
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

    /// Kompositerar VARJE alternativ mot den fulla, redan beräknade masken
    /// (`loadPreviewMask()`) - INTE mot en nedskalad bild. `CIBlendWithMask`
    /// kräver att motiv och mask täcker samma koordinatyta; en nedskalad
    /// bild ihop med en mask i full upplösning skulle ge en felaktigt
    /// förskjuten/felskalad komposition. Miniatyren skalas ner EFTERÅT
    /// (`resized(maxDimension:)`), på samma sätt som `PhotoFilterPickerView`
    /// gör för sina filter-miniatyrer - men till skillnad från Filter (som
    /// kan skala ner FÖRE, billigt, eftersom den inte har någon mask att
    /// hålla i synk) blir varje komposition här dyrare eftersom den måste
    /// köras i full upplösning. Varje alternativ körs därför i en egen
    /// `Task.detached`, en i taget, så huvudtråden aldrig blockeras medan
    /// rutnätet fylls i (miniatyrerna dyker upp en efter en istället för
    /// att sheeten hackar till vid öppning).
    private func generateThumbnails() async {
        guard let mask = await loadPreviewMask() else {
            didFailToLoadMask = true
            return
        }
        let backgroundRemoval = BackgroundRemovalService()
        for option in options {
            let style = option.style.serviceStyle
            let composited = await Task.detached(priority: .userInitiated) {
                try? backgroundRemoval.composite(mask, background: style)
            }.value
            guard let composited else { continue }
            thumbnails[option.key] = composited.resized(maxDimension: 160)
        }
    }
}
