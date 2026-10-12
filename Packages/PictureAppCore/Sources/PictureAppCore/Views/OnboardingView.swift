import SwiftUI

/// Enkel introduktion i tre steg som visas första gången appen öppnas (och
/// kan öppnas igen från Inställningar). Eget stegläge istället för
/// `TabView(.page)` - den sidstilen finns inte på macOS.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step = 0

    private struct Step {
        let systemImage: String
        let title: String
        let text: String
    }

    private var steps: [Step] {
        [
            Step(
                systemImage: "photo.badge.plus",
                title: L("1. Välj en bild"),
                text: L("Hämta en bild från Foton, kameran, webben eller AI - eller klistra in en bild du kopierat.")
            ),
            Step(
                systemImage: "wand.and.stars",
                title: L("2. Gör den till din"),
                text: L("Byt eller ta bort bakgrunden, välj form och filter, lägg på text eller en logotyp. Dra, zooma och vrid direkt på bilden.")
            ),
            Step(
                systemImage: "square.and.arrow.down",
                title: L("3. Spara eller dela"),
                text: L("Tryck Spara eller Dela när du är nöjd. Din pågående redigering sparas automatiskt, så du kan fortsätta senare.")
            ),
        ]
    }

    var body: some View {
        let current = steps[step]
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            Image(systemName: current.systemImage)
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.accent)

            Text(current.title)
                .font(.title2.weight(.semibold))

            Text(current.text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                ForEach(steps.indices, id: \.self) { index in
                    Circle()
                        .fill(index == step ? AppTheme.accent : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }

            HStack(spacing: 16) {
                Button(L("Hoppa över")) { onFinish() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                if step < steps.count - 1 {
                    Button(L("Nästa")) { step += 1 }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(L("Kom igång")) { onFinish() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(minWidth: 380, idealWidth: 440, minHeight: 380, idealHeight: 420)
        .interactiveDismissDisabled()
    }
}
