import SwiftUI

/// Visas när Vision hittar FLERA separata motiv i samma bild (t.ex. två
/// personer, eller en person + en hund) - låter användaren välja vilket
/// eller vilka som ska behållas innan bakgrunden tas bort. Visas ALDRIG när
/// bara ett motiv hittas - då fortsätter det befintliga flödet direkt utan
/// extra steg (se `SearchViewModel.removeBackground()`).
///
/// Varje motiv ritas som en färgad, halvgenomskinlig overlay i sin FAKTISKA
/// form (Visions egen mask för just den instansen, förberäknad i
/// `SearchViewModel`) ovanpå bilden, plus en tryckbar bock-markör vid
/// motivets mitt. Overlayen visar exakt vad som väljs; markören ger en
/// stor, pålitlig tryckyta - att kräva att man träffar motivets exakta
/// pixlar med fingret vore opålitligt för smala motiv (en arm, ett ben)
/// eller när två motiv överlappar.
struct SubjectPickerView: View {
    let baseImage: PlatformImage
    let instances: [SearchViewModel.SubjectPickerInstance]
    let onDone: (Set<Int>) -> Void
    let onCancel: () -> Void

    @State private var selected: Set<Int>

    init(
        baseImage: PlatformImage,
        instances: [SearchViewModel.SubjectPickerInstance],
        initiallySelected: Set<Int>,
        onDone: @escaping (Set<Int>) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.baseImage = baseImage
        self.instances = instances
        self.onDone = onDone
        self.onCancel = onCancel
        self._selected = State(initialValue: initiallySelected)
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Flera motiv hittades")
                .font(.headline)
            Text("Välj vilket eller vilka motiv som ska behållas.")
                .font(.caption)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let displaySize = Self.aspectFitSize(for: baseImage.size, in: geo.size)
                let origin = CGPoint(x: (geo.size.width - displaySize.width) / 2, y: (geo.size.height - displaySize.height) / 2)

                ZStack {
                    Image(platformImage: baseImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)

                    // Färgad silhuett per motiv - bara synlig (halvgenomskinlig)
                    // när motivet är valt, så bilden visar exakt vad som
                    // faktiskt kommer behållas.
                    ForEach(instances) { instance in
                        Image(platformImage: instance.overlayImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .opacity(selected.contains(instance.id) ? 0.5 : 0)
                            .allowsHitTesting(false)
                            .animation(.easeInOut(duration: 0.15), value: selected)
                    }

                    ForEach(instances) { instance in
                        let isSelected = selected.contains(instance.id)
                        Button {
                            toggle(instance.id)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(isSelected ? AppTheme.accent : Color(white: 0, opacity: 0.55))
                                Image(systemName: isSelected ? "checkmark" : "circle")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 30, height: 30)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                            .shadow(radius: 2)
                        }
                        .buttonStyle(.plain)
                        .position(
                            x: origin.x + instance.boundingBox.midX * displaySize.width,
                            y: origin.y + instance.boundingBox.midY * displaySize.height
                        )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .background(CheckerboardBackground())
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text("\(selected.count) av \(instances.count) motiv valda")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Avbryt", role: .cancel) { onCancel() }
                Spacer()
                Button("Klart") { onDone(selected) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
                    .help(selected.isEmpty ? "Välj minst ett motiv." : "")
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 520, minHeight: 480, idealHeight: 580)
    }

    private var aspectRatio: CGFloat {
        let size = baseImage.size
        guard size.width > 0, size.height > 0 else { return 1 }
        return size.width / size.height
    }

    private func toggle(_ id: Int) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    /// Samma letterbox-beräkning som `MaskEditorView.aspectFitSize` - bildens
    /// faktiska visningsyta inuti containern med `.aspectRatio(contentMode: .fit)`,
    /// för att placera markörerna rätt oavsett bildens proportion.
    private static func aspectFitSize(for contentSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard contentSize.width > 0, contentSize.height > 0 else { return containerSize }
        let scale = min(containerSize.width / contentSize.width, containerSize.height / contentSize.height)
        return CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
    }
}
