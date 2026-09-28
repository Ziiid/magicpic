import SwiftUI

/// Skjutreglage för bildkorrigeringar (`ImageAdjustments`) - ljusstyrka,
/// kontrast, mättnad, temperatur, highlights/shadows, skärpa,
/// brusreducering, vinjett. `onChange` anropas vid varje reglageändring
/// (inte bara vid stängning) så förhandsvisningen känns direkt - se
/// `SearchViewModel.setImageAdjustments`, som räknar om en billig
/// CoreImage-förhandsvisning direkt men bara komponerar om det FULLA
/// resultatet (med Vision-masken) om bakgrunden redan bearbetats en gång.
struct ImageAdjustmentsView: View {
    @State private var adjustments: ImageAdjustments
    // Skickas in som ett vanligt värde, inte kopierat till @State - så att
    // varje omritning (när `viewModel.adjustedPreviewImage` uppdateras via
    // `onChange`) visar den SENASTE bilden, inte en frusen ögonblicksbild
    // från när panelen öppnades.
    let previewImage: PlatformImage?
    let onChange: (ImageAdjustments) -> Void
    let onDone: () -> Void

    init(adjustments: ImageAdjustments, previewImage: PlatformImage?, onChange: @escaping (ImageAdjustments) -> Void, onDone: @escaping () -> Void) {
        _adjustments = State(initialValue: adjustments)
        self.previewImage = previewImage
        self.onChange = onChange
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(L("Justera bilden"))
                .font(.headline)

            // Egen förhandsvisning HÄR i panelen - annars är det svårt att
            // se vad ett reglage faktiskt gör medan panelen (särskilt som
            // en macOS-sheet) täcker bilden bakom (rapporterat 2026-09-26).
            ZStack {
                CheckerboardBackground()
                if let previewImage {
                    Image(platformImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            ScrollView {
                VStack(spacing: 14) {
                    slider(L("Ljusstyrka"), systemImage: "sun.max", value: $adjustments.brightness, range: -1...1)
                    slider(L("Kontrast"), systemImage: "circle.lefthalf.filled", value: $adjustments.contrast, range: -1...1)
                    slider(L("Mättnad"), systemImage: "drop", value: $adjustments.saturation, range: -1...1)
                    slider(L("Temperatur"), systemImage: "thermometer.sun", value: $adjustments.temperature, range: -1...1)
                    Divider()
                    slider("Highlights", systemImage: "sun.min", value: $adjustments.highlights, range: 0...1)
                    slider("Shadows", systemImage: "moon", value: $adjustments.shadows, range: 0...1)
                    Divider()
                    slider(L("Skärpa"), systemImage: "triangle", value: $adjustments.sharpness, range: 0...1)
                    slider(L("Brusreducering"), systemImage: "aqi.medium", value: $adjustments.noiseReduction, range: 0...1)
                    slider(L("Vinjett"), systemImage: "circle.dashed", value: $adjustments.vignette, range: 0...1)
                }
                .padding(.horizontal, 4)
            }

            HStack {
                Button(L("Återställ justeringar")) {
                    adjustments = .identity
                    onChange(adjustments)
                }
                .disabled(adjustments.isIdentity)

                Spacer()

                Button(L("Klart")) { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 340, idealWidth: 380, minHeight: 480, idealHeight: 560)
    }

    // `title: String`, redan lokaliserad av anropsstället (`L(...)`) - INTE
    // `LocalizedStringKey`, se `CLAUDE.md`s lokaliseringsavsnitt/
    // `ImagePositionerView`s motsvarande kommentar för varför.
    private func slider(_ title: String, systemImage: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%+.2f", value.wrappedValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { value.wrappedValue },
                    set: { value.wrappedValue = $0; onChange(adjustments) }
                ),
                in: range
            )
        }
    }
}
