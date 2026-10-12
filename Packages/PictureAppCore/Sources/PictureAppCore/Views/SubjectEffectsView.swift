import SwiftUI

/// Skugga och kontur på motivet. Reglagen tillämpas när man släpper dem
/// (varje ändring kör om bildpipelinen), förhandsvisningen uppdateras då.
struct SubjectEffectsView: View {
    let previewImage: PlatformImage?
    let initial: SubjectEffects
    let onChange: (SubjectEffects) -> Void
    let onDone: () -> Void

    @State private var effects: SubjectEffects

    init(previewImage: PlatformImage?, initial: SubjectEffects, onChange: @escaping (SubjectEffects) -> Void, onDone: @escaping () -> Void) {
        self.previewImage = previewImage
        self.initial = initial
        self.onChange = onChange
        self.onDone = onDone
        _effects = State(initialValue: initial)
    }

    private let outlineColors: [Color] = [.white, .black, .yellow, .red, .blue, .green]

    var body: some View {
        VStack(spacing: 14) {
            Text(L("Skugga och kontur"))
                .font(.headline)

            ZStack {
                CheckerboardBackground()
                if let previewImage {
                    Image(platformImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 14) {
                effectSlider(L("Skugga"), systemImage: "shadow", value: $effects.shadow)
                effectSlider(L("Kontur"), systemImage: "square.dashed", value: $effects.outlineWidth)

                if effects.outlineWidth > 0 {
                    HStack(spacing: 10) {
                        Text(L("Konturfärg"))
                            .font(.caption)
                        ForEach(Array(outlineColors.enumerated()), id: \.offset) { _, color in
                            Button {
                                effects.outlineColor = color
                                onChange(effects)
                            } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle().strokeBorder(
                                            effects.outlineColor == color ? AppTheme.accent : Color.secondary.opacity(0.4),
                                            lineWidth: effects.outlineColor == color ? 3 : 1
                                        )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            HStack {
                Button(L("Ta bort effekter")) {
                    effects = .none
                    onChange(effects)
                }
                .disabled(effects.isNone)

                Spacer()

                Button(L("Klart")) { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 340, idealWidth: 400, minHeight: 440, idealHeight: 500)
    }

    private func effectSlider(_ title: String, systemImage: String, value: Binding<Double>) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .frame(width: 100, alignment: .leading)
            Slider(value: value, in: 0...1) { editing in
                if !editing { onChange(effects) }
            }
            .tint(AppTheme.accent)
        }
    }
}
