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
    let onChange: (ImageAdjustments) -> Void
    let onDone: () -> Void

    init(adjustments: ImageAdjustments, onChange: @escaping (ImageAdjustments) -> Void, onDone: @escaping () -> Void) {
        _adjustments = State(initialValue: adjustments)
        self.onChange = onChange
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Justera bilden")
                .font(.headline)

            ScrollView {
                VStack(spacing: 14) {
                    slider("Ljusstyrka", systemImage: "sun.max", value: $adjustments.brightness, range: -1...1)
                    slider("Kontrast", systemImage: "circle.lefthalf.filled", value: $adjustments.contrast, range: -1...1)
                    slider("Mättnad", systemImage: "drop", value: $adjustments.saturation, range: -1...1)
                    slider("Temperatur", systemImage: "thermometer.sun", value: $adjustments.temperature, range: -1...1)
                    Divider()
                    slider("Highlights", systemImage: "sun.min", value: $adjustments.highlights, range: 0...1)
                    slider("Shadows", systemImage: "moon", value: $adjustments.shadows, range: 0...1)
                    Divider()
                    slider("Skärpa", systemImage: "triangle", value: $adjustments.sharpness, range: 0...1)
                    slider("Brusreducering", systemImage: "aqi.medium", value: $adjustments.noiseReduction, range: 0...1)
                    slider("Vinjett", systemImage: "circle.dashed", value: $adjustments.vignette, range: 0...1)
                }
                .padding(.horizontal, 4)
            }

            HStack {
                Button("Återställ justeringar") {
                    adjustments = .identity
                    onChange(adjustments)
                }
                .disabled(adjustments.isIdentity)

                Spacer()

                Button("Klart") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 340, idealWidth: 380, minHeight: 480, idealHeight: 560)
    }

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
