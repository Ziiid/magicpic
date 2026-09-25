import SwiftUI

/// Penselverktyg för att manuellt lägga till eller ta bort delar av den
/// Vision-genererade masken - t.ex. hårstrån eller skuggor den automatiska
/// analysen missade.
///
/// Navigering (nyp/dra för att zooma/panorera) och målning delar båda
/// enfingers-drag som gest, så de hålls som två uttryckliga, ömsesidigt
/// uteslutande lägen istället för att försöka särskilja dem automatiskt -
/// enklare att resonera om korrekt än att gissa på gestprioritet, och
/// fungerar identiskt med mus på Mac och touch på iPhone/iPad.
///
/// Målningsgesten sitter på ett OSKALAT overlay-lager ovanpå den
/// zoomade/panorerade bilden, så pekpunkten alltid rapporteras i enkla
/// 0...containerSize-koordinater oavsett aktuell zoomnivå - transformen
/// inverteras sedan för hand (se `imagePoint`) för att räkna ut var i
/// maskens PIXELDATA man faktiskt pekar. Det är mer tillförlitligt än att
/// lita på att SwiftUI rapporterar gestkoordinater korrekt genom en
/// `scaleEffect`/`offset`-kedja.
struct MaskEditorView: View {
    let baseImage: PlatformImage
    let onDone: (EditableMask) -> Void
    let onCancel: () -> Void

    @State private var editableMask: EditableMask
    @State private var preview: PlatformImage
    @State private var brushRadius: CGFloat = 36
    @State private var isAdding = true
    @State private var mode: Mode = .paint
    @State private var brushCursor: CGPoint?

    @State private var committedScale: CGFloat = 1
    @State private var committedOffset: CGSize = .zero
    @GestureState private var liveDrag: CGSize = .zero
    @GestureState private var liveMagnification: CGFloat = 1

    private let backgroundRemoval = BackgroundRemovalService()

    enum Mode: String, CaseIterable, Identifiable {
        case paint = "Måla"
        case navigate = "Navigera"
        var id: String { rawValue }
    }

    init(baseImage: PlatformImage, editableMask: EditableMask, onDone: @escaping (EditableMask) -> Void, onCancel: @escaping () -> Void) {
        self.baseImage = baseImage
        self._editableMask = State(initialValue: editableMask)
        self._preview = State(initialValue: baseImage)
        self.onDone = onDone
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("Finjustera urklippet")
                .font(.headline)
            Text(mode == .paint
                 ? "Dra för att lägga till eller ta bort delar av motivet."
                 : "Dra för att panorera, nyp för att zooma in och måla precisare.")
                .font(.caption)
                .foregroundStyle(.secondary)

            GeometryReader { geo in
                let containerSize = geo.size
                let scale = max(committedScale * liveMagnification, 1)
                let offset = CGSize(width: committedOffset.width + liveDrag.width, height: committedOffset.height + liveDrag.height)

                let visual = ZStack {
                    CheckerboardBackground()
                    Image(platformImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                .frame(width: containerSize.width, height: containerSize.height)
                .scaleEffect(scale)
                .offset(offset)
                .clipped()

                ZStack {
                    visual

                    if mode == .paint {
                        Color.clear
                            .frame(width: containerSize.width, height: containerSize.height)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        paint(at: value.location, containerSize: containerSize, scale: scale, offset: offset)
                                    }
                                    .onEnded { _ in
                                        brushCursor = nil
                                        Task { await recomposite() }
                                    }
                            )
                        if let brushCursor {
                            Circle()
                                .stroke(isAdding ? Color.green : Color.red, lineWidth: 2)
                                .frame(width: brushRadius * 2, height: brushRadius * 2)
                                .position(brushCursor)
                                .allowsHitTesting(false)
                        }
                    } else {
                        Color.clear
                            .frame(width: containerSize.width, height: containerSize.height)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .updating($liveDrag) { value, state, _ in state = value.translation }
                                    .onEnded { value in
                                        let newOffset = CGSize(
                                            width: committedOffset.width + value.translation.width,
                                            height: committedOffset.height + value.translation.height
                                        )
                                        committedOffset = Self.clampOffset(newOffset, scale: committedScale, containerSize: containerSize)
                                    }
                            )
                            .simultaneousGesture(
                                MagnificationGesture()
                                    .updating($liveMagnification) { value, state, _ in state = value }
                                    .onEnded { value in
                                        committedScale = max(committedScale * value, 1)
                                        committedOffset = Self.clampOffset(committedOffset, scale: committedScale, containerSize: containerSize)
                                    }
                            )
                    }
                }
            }
            .background(Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Picker("Läge", selection: $mode) {
                ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
            }
            .pickerStyle(.segmented)

            if mode == .paint {
                Picker("Pensel", selection: $isAdding) {
                    Text("Lägg till").tag(true)
                    Text("Ta bort").tag(false)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Penselstorlek")
                    Slider(value: $brushRadius, in: 10...80)
                }
            }

            HStack {
                Button("Avbryt", role: .cancel) { onCancel() }
                Spacer()
                Button("Klart") { onDone(editableMask) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 420, idealWidth: 520, minHeight: 520, idealHeight: 620)
        .task { await recomposite() }
    }

    private func paint(at location: CGPoint, containerSize: CGSize, scale: CGFloat, offset: CGSize) {
        let maskSize = CGSize(width: editableMask.width, height: editableMask.height)
        let displaySize = Self.aspectFitSize(for: maskSize, in: containerSize)
        let point = Self.imagePoint(
            from: location,
            containerSize: containerSize,
            displaySize: displaySize,
            scale: scale,
            offset: offset,
            maskSize: maskSize
        )
        let pixelRadius = (brushRadius / scale) * (CGFloat(editableMask.width) / displaySize.width)
        editableMask.paint(at: point, radius: pixelRadius, adding: isAdding)
        brushCursor = location
    }

    /// Bildens faktiska visningsstorlek inuti `containerSize` med
    /// `.aspectRatio(contentMode: .fit)` - bilden fyller INTE nödvändigtvis
    /// hela containern, den brevlådas (letterboxas) om proportionerna inte
    /// stämmer exakt överens, med tomrum centrerat på sidorna/upptill-
    /// nedtill. Måste räknas ut innan en klickpunkt kan mappas till en
    /// bildpixel - annars pekar penseln systematiskt fel så fort bildens
    /// proportion skiljer sig från containerns (upptäckt 2026-09-25).
    private static func aspectFitSize(for contentSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard contentSize.width > 0, contentSize.height > 0 else { return containerSize }
        let scale = min(containerSize.width / contentSize.width, containerSize.height / contentSize.height)
        return CGSize(width: contentSize.width * scale, height: contentSize.height * scale)
    }

    /// Inverterar `scaleEffect(scale).offset(offset)`-transformen för hand
    /// för att räkna ut vilken bildpixel en pekpunkt i det oskalade
    /// overlayet motsvarar. Går via bildens faktiska (letterboxade)
    /// visningsyta (`displaySize`, centrerad i containern) - inte hela
    /// containern - annars stämmer inte mappningen när bildens proportion
    /// skiljer sig från containerns.
    private static func imagePoint(from containerPoint: CGPoint, containerSize: CGSize, displaySize: CGSize, scale: CGFloat, offset: CGSize, maskSize: CGSize) -> CGPoint {
        let center = CGPoint(x: containerSize.width / 2, y: containerSize.height / 2)
        let unscaledX = (containerPoint.x - center.x - offset.width) / scale + center.x
        let unscaledY = (containerPoint.y - center.y - offset.height) / scale + center.y

        let imageOrigin = CGPoint(
            x: (containerSize.width - displaySize.width) / 2,
            y: (containerSize.height - displaySize.height) / 2
        )
        return CGPoint(
            x: (unscaledX - imageOrigin.x) / displaySize.width * maskSize.width,
            y: (unscaledY - imageOrigin.y) / displaySize.height * maskSize.height
        )
    }

    private static func clampOffset(_ offset: CGSize, scale: CGFloat, containerSize: CGSize) -> CGSize {
        let maxX = containerSize.width * (scale - 1) / 2
        let maxY = containerSize.height * (scale - 1) / 2
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    /// Renderar om förhandsvisningen mot transparent bakgrund så man ser
    /// exakt vad masken behåller/tar bort (rutmönster = borttaget). Den dyra
    /// CoreImage-renderingen körs bara här - vid gestens slut, inte per
    /// penseldrag - medan själva penseldraget skriver direkt i
    /// pixelbufferten (billigt) för full precision.
    private func recompositePreview() async -> PlatformImage? {
        guard let originalCG = baseImage.cgImageRepresentation else { return nil }
        let mask = editableMask
        let renderer = backgroundRemoval
        return try? await Task.detached(priority: .userInitiated) {
            let foreground = BackgroundRemovalService.ForegroundMask(original: originalCG, mask: mask.pixelBuffer)
            return try renderer.composite(foreground, background: .transparent)
        }.value
    }

    private func recomposite() async {
        if let result = await recompositePreview() {
            // Utan den uttryckliga hoppen tillbaka finns ingen garanti att
            // `Task.detached`-jobbet i `recompositePreview()` återupptas på
            // huvudtråden - och att skriva till @State utanför huvudtråden
            // är odefinierat beteende.
            await MainActor.run { preview = result }
        }
    }
}
