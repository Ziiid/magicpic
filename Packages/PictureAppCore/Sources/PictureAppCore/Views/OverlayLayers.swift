import SwiftUI

/// Ett markerbart, flyttbart lager ovanpå formramningen
/// (`SubjectFramingCanvas`) - delad mekanik för text (`TextOverlayLayer`)
/// och logotyp (`LogoOverlayLayer`). Samma interaktionsmodell som i
/// Persona-appens `SelectionChrome`/`useDraggableTransform`: ett tryck (eller
/// en gest) MARKERAR objektet med en grön ram, och det markerade objektet har
/// ett gripbart hörn nere till höger som skalar OCH vrider med ETT finger/en
/// musmarkör (avstånd från objektets centrum styr storleken, vinkeln runt
/// centrum styr rotationen) - alternativ till tvåfingers-nyp/vrid, som ändå
/// fungerar också. Övre vänster hörn tar bort objektet; övre höger är en
/// valfri extraknapp (redigera för text, spegelvänd för logotyp).
///
/// Placeringen är relativ till kanvasen (se `TextOverlay`/`LogoOverlay`) och
/// måste ge samma resultat som exporten ritar (`TextOverlayService`/
/// `LogoOverlayService`): storlek = `size * kanvasbredd`, mittpunkt =
/// kanvasens mitt + `offset`. Ritas medvetet INTE klippt till formens siluett
/// - annars vore ett objekt utanför formen osynligt OCH omöjligt att ta tag i
/// igen (formens kontur syns ändå som vit linje).
struct SelectableOverlayLayer<Content: View>: View {
    @Binding var size: CGFloat
    @Binding var offset: CGSize
    @Binding var rotation: Angle
    @Binding var isSelected: Bool
    let sizeRange: ClosedRange<CGFloat>
    let containerSize: CGSize
    let onCommit: () -> Void
    let onDelete: () -> Void
    // Hörnknappen uppe till höger - "redigera" (text) eller "spegelvänd"
    // (logotyp); ingen av dem om anroparen inte skickar någon.
    var onEdit: (() -> Void)?
    var onFlip: (() -> Void)?
    // Själva innehållet, ritat i den aktuella (live) storleken som andel av
    // kanvasens bredd.
    @ViewBuilder let content: (CGFloat) -> Content

    @GestureState private var liveDrag: CGSize = .zero
    @GestureState private var liveMagnification: CGFloat = 1
    @GestureState private var liveRotation: Angle = .zero
    // Storlek/rotation vid starten av ett hörn-drag - värdena skrivs INTE
    // till bindningarna under draget, så utgångsläget måste sparas separat.
    // `nil` = inget hörn-drag pågår.
    @State private var gripStart: (size: CGFloat, rotation: Angle)?
    // Pågående hörn-dragets LIVE-värden, lokalt i den här vyn - att skriva
    // dem till view model:n (en `@Published`) för varje pekarhändelse ritade
    // om HELA `DetailPanel` per bildruta och gjorde draget segt. Skrivs till
    // bindningarna först när draget släpps.
    @State private var gripLive: (size: CGFloat, rotation: Angle)?

    private static var paddingAroundContent: CGFloat { 24 }
    private static var frameInset: CGFloat { 10 }
    private static var coordinateSpaceName: String { "overlayCanvas" }

    private func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, sizeRange.lowerBound), sizeRange.upperBound)
    }

    private func finishManipulation() {
        isSelected = true
        onCommit()
    }

    /// Objektets mittpunkt i kanvasens koordinater (utan pågående live-drag -
    /// hörn-draget och en dra-gest pågår aldrig samtidigt).
    private var center: CGPoint {
        CGPoint(
            x: containerSize.width / 2 + offset.width * containerSize.width,
            y: containerSize.height / 2 + offset.height * containerSize.height
        )
    }

    var body: some View {
        let liveSize = gripLive?.size ?? clamped(size * liveMagnification)
        let liveAngle = gripLive?.rotation ?? (rotation + liveRotation)

        content(liveSize)
            .padding(Self.paddingAroundContent)
            .overlay { if isSelected { selectionChrome } }
            .contentShape(Rectangle())
            .rotationEffect(liveAngle)
            .offset(
                x: offset.width * containerSize.width + liveDrag.width,
                y: offset.height * containerSize.height + liveDrag.height
            )
            .gesture(
                DragGesture()
                    .updating($liveDrag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        offset = CGSize(
                            width: offset.width + value.translation.width / containerSize.width,
                            height: offset.height + value.translation.height / containerSize.height
                        )
                        finishManipulation()
                    }
                    .simultaneously(with:
                        MagnifyGesture()
                            .updating($liveMagnification) { value, state, _ in state = value.magnification }
                            .onEnded { value in
                                size = clamped(size * value.magnification)
                                finishManipulation()
                            }
                    )
                    .simultaneously(with:
                        RotateGesture()
                            .updating($liveRotation) { value, state, _ in state = value.rotation }
                            .onEnded { value in
                                rotation += value.rotation
                                finishManipulation()
                            }
                    )
            )
            .onTapGesture { isSelected = true }
            .frame(width: containerSize.width, height: containerSize.height)
            // Fast, orörligt koordinatsystem för hörn-gripet (objektet självt
            // är roterat/förskjutet, så dess egna koordinater duger inte).
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
            if let onEdit {
                chromeButton(systemImage: "pencil", fill: AppTheme.accent, action: onEdit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            } else if let onFlip {
                chromeButton(systemImage: "arrow.left.and.right", fill: AppTheme.accent, action: onFlip)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
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
    /// runt centrum) - se strukturens dokumentation.
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
                        if gripStart == nil { gripStart = (size, rotation) }
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
                            clamped(start.size * currentDistance / startDistance),
                            start.rotation + Angle(radians: Double(deltaAngle))
                        )
                    }
                    .onEnded { _ in
                        if let live = gripLive {
                            size = live.size
                            rotation = live.rotation
                        }
                        gripStart = nil
                        gripLive = nil
                        onCommit()
                    }
            )
    }
}

/// Textens lager - se `SelectableOverlayLayer`. Teckenstorlek =
/// `overlay.size * kanvasbredd`, måste matcha `TextOverlayService`.
struct TextOverlayLayer: View {
    @Binding var overlay: TextOverlay
    @Binding var isSelected: Bool
    let containerSize: CGSize
    let onCommit: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SelectableOverlayLayer(
            size: $overlay.size,
            offset: $overlay.offset,
            rotation: $overlay.rotation,
            isSelected: $isSelected,
            sizeRange: TextOverlay.minSize...TextOverlay.maxSize,
            containerSize: containerSize,
            onCommit: onCommit,
            onDelete: onDelete,
            onEdit: onEdit,
            onFlip: nil,
            content: { size in
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
            }
        )
    }
}

/// Logotypens lager - se `SelectableOverlayLayer`. Bredd =
/// `logo.size * kanvasbredd`, höjden följer bildens eget bildförhållande
/// (måste matcha `LogoOverlayService`).
struct LogoOverlayLayer: View {
    @Binding var logo: LogoOverlay
    @Binding var isSelected: Bool
    let containerSize: CGSize
    let onCommit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        SelectableOverlayLayer(
            size: $logo.size,
            offset: $logo.offset,
            rotation: $logo.rotation,
            isSelected: $isSelected,
            sizeRange: LogoOverlay.minSize...LogoOverlay.maxSize,
            containerSize: containerSize,
            onCommit: onCommit,
            onDelete: onDelete,
            onEdit: nil,
            onFlip: { logo.isFlipped.toggle(); onCommit() },
            content: { size in
                Image(platformImage: logo.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size * containerSize.width)
                    .scaleEffect(x: logo.isFlipped ? -1 : 1, y: 1)
            }
        )
    }
}
