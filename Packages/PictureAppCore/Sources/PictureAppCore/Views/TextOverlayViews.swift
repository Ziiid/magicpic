import SwiftUI

/// Redigeringsrutan för texten: skriv, välj teckensnitt/färg/storlek/
/// skugga. Själva placeringen görs direkt på bilden (dra/nyp/vrid), men
/// "Centrera" nollställer den om texten hamnat utom räckhåll.
struct TextOverlayEditorView: View {
    @Binding var overlay: TextOverlay
    let onDelete: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(L("Text"))
                .font(.headline)

            // Liten förhandsvisning - själva bilden skyms av rutan.
            ZStack {
                CheckerboardBackground()
                Text(overlay.text.isEmpty ? " " : overlay.text)
                    .font(.custom(overlay.fontStyle.postScriptName, fixedSize: 34))
                    .foregroundStyle(overlay.color)
                    .shadow(color: overlay.hasShadow ? .black.opacity(0.6) : .clear, radius: 2, x: 0, y: 2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .padding(.horizontal, 12)
            }
            .frame(height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            TextField(L("Din text"), text: $overlay.text)
                .textFieldStyle(.roundedBorder)

            Picker(L("Teckensnitt"), selection: $overlay.fontStyle) {
                ForEach(TextFontStyle.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.menu)

            HStack {
                Text(L("Storlek"))
                Slider(value: $overlay.size, in: TextOverlay.minSize...TextOverlay.maxSize)
            }

            HStack(spacing: 8) {
                ForEach(Array(BackgroundOption.presetColors.enumerated()), id: \.offset) { _, color in
                    Button {
                        overlay.color = color
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(overlay.color == color ? AppTheme.accent : Color.secondary.opacity(0.3), lineWidth: overlay.color == color ? 3 : 1))
                    }
                    .buttonStyle(.plain)
                }
                ColorPicker(L("Färg"), selection: $overlay.color, supportsOpacity: false)
                    .labelsHidden()
            }

            Toggle(L("Skugga"), isOn: $overlay.hasShadow)

            HStack {
                Button(L("Ta bort text"), role: .destructive) { onDelete() }
                Button(L("Centrera")) {
                    overlay.offset = .zero
                    overlay.rotation = .zero
                }
                Spacer()
                Button(L("Klart")) { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 360, idealWidth: 420, minHeight: 380)
    }
}
