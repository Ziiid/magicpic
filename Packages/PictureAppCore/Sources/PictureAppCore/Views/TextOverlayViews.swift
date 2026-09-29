import SwiftUI

/// Textlagret i den inbäddade formramningen (`SubjectFramingCanvas`).
/// Samma interaktionsmodell som i Persona-appens `SelectionChrome`/
/// `useDraggableTransform`: ett tryck (eller en gest) på texten MARKERAR den
/// med en grön ram, och den markerade texten har ett gripbart hörn nere till
/// höger som skalar OCH vrider med ETT finger/en musmarkör (avstånd från
/// textens centrum styr storleken, vinkeln runt centrum styr rotationen) -
/// alternativ till tvåfingers-nyp/vrid, som ändå fungerar också. Övre vänster
/// hörn tar bort texten, övre höger öppnar redigeraren.
///
/// Placeringen är relativ till kanvasen (se `TextOverlay`) och måste ge
/// samma resultat som `TextOverlayService` ritar vid export: teckenstorlek =
/// `overlay.size * kanvasbredd`, mittpunkt = kanvasens mitt + `overlay.offset`.
/// Ritas medvetet INTE klippt till formens siluett - annars vore en text
/// utanför formen osynlig OCH omöjlig att ta tag i igen (formens kontur syns
/// ändå som vit linje).
struct TextOverlayLayer: View {
    @Binding var overlay: TextOverlay
    @Binding var isSelected: Bool
    let containerSize: CGSize
    let onCommit: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @GestureState private var liveDrag: CGSize = .zero
    @GestureState private var liveMagnification: CGFloat = 1
    @GestureState private var liveRotation: Angle = .zero
    // Storlek/rotation vid starten av ett hörn-drag - `overlay` skrivs LIVE
    // under draget, så utgångsläget måste sparas separat. `nil` = inget
    // hörn-drag pågår.
    @State private var gripStart: (size: CGFloat, rotation: Angle)?
    // Pågående hörn-dragets LIVE-värden, lokalt i den här vyn - att skriva
    // dem till `overlay` (en `@Published` i view model:n) för varje
    // pekarhändelse ritade om HELA `DetailPanel` per bildruta och gjorde
    // draget segt. Skrivs till `overlay` först när draget släpps.
    @State private var gripLive: (size: CGFloat, rotation: Angle)?

    private static let paddingAroundText: CGFloat = 24
    private static let frameInset: CGFloat = 10
    private static let coordinateSpaceName = "textOverlayCanvas"

    private func finishManipulation() {
        isSelected = true
        onCommit()
    }

    /// Textens mittpunkt i kanvasens koordinater (utan pågående live-drag -
    /// hörn-draget och en dra-gest pågår aldrig samtidigt).
    private var center: CGPoint {
        CGPoint(
            x: containerSize.width / 2 + overlay.offset.width * containerSize.width,
            y: containerSize.height / 2 + overlay.offset.height * containerSize.height
        )
    }

    var body: some View {
        let size = gripLive?.size ?? min(max(overlay.size * liveMagnification, TextOverlay.minSize), TextOverlay.maxSize)
        let rotation = gripLive?.rotation ?? (overlay.rotation + liveRotation)
        let fontSize = size * containerSize.width

        Text(overlay.text)
            .font(.custom(overlay.fontStyle.postScriptName, fixedSize: fontSize))
            .foregroundStyle(overlay.color)
            .shadow(
                color: overlay.hasShadow ? .black.opacity(0.6) : .clear,
                radius: fontSize * 0.06,
                x: 0,
                y: fontSize * 0.06
            )
            .fixedSize()
            .padding(Self.paddingAroundText)
            .overlay { if isSelected { selectionChrome } }
            .contentShape(Rectangle())
            .rotationEffect(rotation)
            .offset(
                x: overlay.offset.width * containerSize.width + liveDrag.width,
                y: overlay.offset.height * containerSize.height + liveDrag.height
            )
            .gesture(
                DragGesture()
                    .updating($liveDrag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        overlay.offset = CGSize(
                            width: overlay.offset.width + value.translation.width / containerSize.width,
                            height: overlay.offset.height + value.translation.height / containerSize.height
                        )
                        finishManipulation()
                    }
                    .simultaneously(with:
                        MagnifyGesture()
                            .updating($liveMagnification) { value, state, _ in state = value.magnification }
                            .onEnded { value in
                                overlay.size = min(max(overlay.size * value.magnification, TextOverlay.minSize), TextOverlay.maxSize)
                                finishManipulation()
                            }
                    )
                    .simultaneously(with:
                        RotateGesture()
                            .updating($liveRotation) { value, state, _ in state = value.rotation }
                            .onEnded { value in
                                overlay.rotation += value.rotation
                                finishManipulation()
                            }
                    )
            )
            .onTapGesture { isSelected = true }
            .frame(width: containerSize.width, height: containerSize.height)
            // Fast, orörligt koordinatsystem för hörn-gripet (texten själv är
            // roterad/förskjuten, så dess egna koordinater duger inte).
            .coordinateSpace(name: Self.coordinateSpaceName)
    }

    // MARK: - Markeringsram

    private var selectionChrome: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(AppTheme.accent, lineWidth: 2)
                .padding(Self.frameInset)
                .allowsHitTesting(false)

            chromeButton(systemImage: "xmark", fill: Color(red: 0.85, green: 0.33, blue: 0.31), action: onDelete)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            chromeButton(systemImage: "pencil", fill: AppTheme.accent, action: onEdit)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            grip
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    private func chromeButton(systemImage: String, fill: Color, action: @escaping () -> Void) -> some View {
        Circle()
            .fill(fill)
            .overlay(Circle().strokeBorder(AppTheme.onAccent, lineWidth: 2))
            .overlay(Image(systemName: systemImage).font(.system(size: 10, weight: .bold)).foregroundStyle(AppTheme.onAccent))
            .frame(width: 24, height: 24)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            // Större osynlig träffyta än den synliga cirkeln (tummen).
            .padding(4)
            .contentShape(Rectangle())
            .onTapGesture { action() }
    }

    /// Enfingers-handtaget: skalar (avstånd från centrum) och vrider (vinkel
    /// runt centrum) - se filens dokumentation.
    private var grip: some View {
        Circle()
            .fill(AppTheme.accent)
            .overlay(Circle().strokeBorder(AppTheme.onAccent, lineWidth: 2))
            .overlay(Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 9, weight: .bold)).foregroundStyle(AppTheme.onAccent))
            .frame(width: 24, height: 24)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .padding(4)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpaceName))
                    .onChanged { value in
                        if gripStart == nil { gripStart = (overlay.size, overlay.rotation) }
                        guard let start = gripStart else { return }
                        let origin = center
                        let startVector = CGPoint(x: value.startLocation.x - origin.x, y: value.startLocation.y - origin.y)
                        let currentVector = CGPoint(x: value.location.x - origin.x, y: value.location.y - origin.y)
                        let startDistance = max(hypot(startVector.x, startVector.y), 1)
                        let currentDistance = hypot(currentVector.x, currentVector.y)
                        // Undvik ryck när pekaren passerar precis över centrum.
                        guard currentDistance > 4 else { return }
                        let deltaAngle = atan2(currentVector.y, currentVector.x) - atan2(startVector.y, startVector.x)
                        gripLive = (
                            min(max(start.size * currentDistance / startDistance, TextOverlay.minSize), TextOverlay.maxSize),
                            start.rotation + Angle(radians: Double(deltaAngle))
                        )
                    }
                    .onEnded { _ in
                        if let live = gripLive {
                            overlay.size = live.size
                            overlay.rotation = live.rotation
                        }
                        gripStart = nil
                        gripLive = nil
                        onCommit()
                    }
            )
    }
}

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
