import SwiftUI
import UniformTypeIdentifiers

struct DetailPanel: View {
    @ObservedObject var viewModel: SearchViewModel
    @State private var showBackgroundImporter = false
    @State private var showColorPicker = false
    @State private var showAdjustments = false
    @State private var showPhotoFilters = false

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                if viewModel.isLoadingDetail {
                    ProgressView("Laddar bild…")
                        .padding(40)
                } else if let original = viewModel.originalImage {
                    // Alltid den inbäddade, dra-/nyp-/vridbara ramningsytan -
                    // inget separat "justera position"-läge att växla till.
                    // Källan är den bakgrundskompositerade bilden när den
                    // finns (så vald bakgrund syns medan man justerar,
                    // istället för att se ut som att bakgrunden "kommer
                    // tillbaka"), annars det obehandlade originalet.
                    VStack(spacing: 8) {
                        SubjectFramingCanvas(
                            image: viewModel.compositedImage ?? viewModel.adjustedPreviewImage ?? original,
                            shape: viewModel.outputShape,
                            aspectRatio: viewModel.outputShape == .rectangle ? previewAspectRatio : 1,
                            transform: $viewModel.outputShapeTransform,
                            onCommit: { viewModel.commitOutputShapeTransform() }
                        )
                        .padding()

                        Text("Dra för att flytta, nyp för att zooma, vrid med två fingrar för att rotera.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Kunde inte ladda bilden.")
                        .foregroundStyle(.secondary)
                        .padding(40)
                }
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if viewModel.isProcessing {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Bearbetar…")
                }
                .foregroundStyle(.secondary)
                .font(.caption)
            }

            // Tre uttryckligen skilda rader (inte bara "vad som får plats") -
            // grupperade efter VAD de gör i arbetsflödet, inte i den ordning
            // de råkade läggas till:
            //   1. Historik - metakontroller OM redigeringen (inte en
            //      redigering i sig).
            //   2. Redigeringsverktyg - själva kärnarbetsflödet, i den
            //      ordning man rimligen använder dem (bakgrund → form →
            //      stil → finjustering → motiv/mask).
            //   3. Utdata - vad som händer med RESULTATET.
            // Varje rad är fortfarande en `FlowLayout` (inte en fast
            // `HStack`) som säkerhetsnät om en rad ändå inte får plats i
            // bredd på en smal skärm (se `Support/FlowLayout.swift`,
            // ursprungligen byggd för just det problemet 2026-09-26).
            VStack(alignment: .leading, spacing: 8) {
                // Rad 1: Historik.
                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    Button {
                        viewModel.undo()
                    } label: {
                        Label("Ångra", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.nativeToolbar)
                    .disabled(!viewModel.canUndo)
                    .help("Ångra senaste ändringen.")

                    Button {
                        viewModel.redo()
                    } label: {
                        Label("Gör om", systemImage: "arrow.uturn.forward")
                    }
                    .buttonStyle(.nativeToolbar)
                    .disabled(!viewModel.canRedo)
                    .help("Gör om den senast ångrade ändringen.")

                    Button {
                        viewModel.restoreOriginal()
                    } label: {
                        Label("Återställ till original", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.nativeToolbar)
                    .disabled(!hasChanges)
                    .help("Kasta bakgrunds-/form-/positioneringsval och gå tillbaka till originalbilden.")
                }

                // Rad 2: Redigeringsverktyg. Ingen egen "Ta bort bakgrund"-
                // knapp - "Ingen (genomskinlig)" under Bakgrund-menyn gör
                // exakt samma sak, en egen knapp för det var bara en
                // dubblett (rapporterat 2026-09-25).
                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    backgroundMenu

                    shapeMenu

                    Button {
                        showPhotoFilters = true
                    } label: {
                        Label("Filter", systemImage: "camera.filters")
                    }
                    .buttonStyle(.nativeToolbar)
                    .disabled(viewModel.originalImage == nil)
                    .help("Färdiga bildstilar - svartvitt, sepia, röntgen, m.fl.")

                    Button {
                        showAdjustments = true
                    } label: {
                        Label("Justera", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.nativeToolbar)
                    .disabled(viewModel.originalImage == nil)
                    .help("Ljusstyrka, kontrast, mättnad, skärpa, temperatur, highlights/shadows, brusreducering, vinjett.")

                    if viewModel.hasMultipleSubjects {
                        Button {
                            viewModel.reopenSubjectPicker()
                        } label: {
                            Label("Motiv…", systemImage: "checkmark.circle")
                        }
                        .buttonStyle(.nativeToolbar)
                        .help("Välj om vilket eller vilka motiv som ska behållas.")
                    }

                    // Native, INTE hero - penseln KORRIGERAR vad Vision
                    // missade, den är inte appens primära löfte (det är
                    // Bakgrund + Exportera, se motiveringen vid
                    // `backgroundMenu`).
                    Button {
                        viewModel.beginMaskEditing()
                    } label: {
                        Label("Finjustera", systemImage: "paintbrush")
                    }
                    .buttonStyle(.nativeToolbar)
                    .disabled(viewModel.processedImage == nil)
                    .help("Måla för hand för att lägga till eller ta bort delar av urklippet.")
                }

                // Rad 3: Utdata.
                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    formatMenu
                    exportCluster
                }
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity)
        // Justera- och Filter-panelerna tillåter FLERA ändringar (varje
        // reglageutslag/filtertryck) innan man stänger - de ska bli ETT
        // enda undo-steg för hela sessionen, inte ett steg VAR. `onChange`
        // (inte bara sheet-vyns egen "Klart"-knapp) fångar även att panelen
        // sweps ner utan att trycka Klart uttryckligen.
        .onChange(of: showAdjustments) { _, isPresented in
            if isPresented {
                viewModel.beginEditSession()
            } else {
                viewModel.endEditSession()
            }
        }
        .onChange(of: showPhotoFilters) { _, isPresented in
            if isPresented {
                viewModel.beginEditSession()
            } else {
                viewModel.endEditSession()
            }
        }
        .fileImporter(isPresented: $showBackgroundImporter, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                Task { await viewModel.setCustomBackground(from: url) }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $viewModel.backgroundPositioningRequest) { request in
            ImagePositionerView(
                title: "Justera bakgrundsbilden",
                subtitle: "Dra för att flytta, nyp för att zooma, vrid med två fingrar för att rotera.",
                image: request.image,
                previewAspectRatio: previewAspectRatio,
                clipShape: AnyShape(Rectangle()),
                doneLabel: "Använd bakgrund",
                initialTransform: request.initialTransform,
                onDone: { transform in viewModel.confirmCustomBackground(image: request.image, transform: transform) },
                onCancel: { viewModel.cancelCustomBackgroundPositioning() }
            )
        }
        .sheet(isPresented: $showPhotoFilters) {
            if let original = viewModel.originalImage {
                PhotoFilterPickerView(
                    baseImage: original,
                    currentFilter: viewModel.photoFilter,
                    onSelect: { viewModel.setPhotoFilter($0) },
                    onDone: { showPhotoFilters = false }
                )
            }
        }
        .sheet(isPresented: $showAdjustments) {
            ImageAdjustmentsView(
                adjustments: viewModel.imageAdjustments,
                previewImage: viewModel.adjustedPreviewImage ?? viewModel.originalImage,
                onChange: { viewModel.setImageAdjustments($0) },
                onDone: { showAdjustments = false }
            )
        }
        .sheet(item: $viewModel.maskEditingRequest) { request in
            MaskEditorView(
                baseImage: request.baseImage,
                editableMask: request.editableMask,
                onDone: { editedMask in viewModel.applyEditedMask(editedMask) },
                onCancel: { viewModel.cancelMaskEditing() }
            )
        }
        .sheet(item: $viewModel.subjectSelectionRequest) { request in
            SubjectPickerView(
                baseImage: request.baseImage,
                instances: request.instances,
                initiallySelected: request.initiallySelected,
                onDone: { selected in viewModel.confirmSubjectSelection(selected) },
                onCancel: { viewModel.cancelSubjectSelection() }
            )
        }
        .sheet(isPresented: $showColorPicker) {
            VStack(spacing: 20) {
                Text("Bakgrundsfärg")
                    .font(.headline)

                // Vanliga färger direkt klickbara - innan krävdes ett extra
                // klick på ColorPicker-swatchen för att öppna systemets
                // färgpanel bara för att välja en vanlig färg (rapporterat
                // 2026-09-25).
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(Self.presetColors, id: \.self) { color in
                        Button {
                            viewModel.setBackgroundStyle(.color(color))
                            showColorPicker = false
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                                .overlay(Circle().strokeBorder(AppTheme.accent, lineWidth: isSelectedColor(color) ? 3 : 0))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()

                ColorPicker(
                    "Fler färger…",
                    selection: Binding(
                        get: {
                            if case .color(let color) = viewModel.backgroundStyle { return color }
                            return .white
                        },
                        set: { viewModel.setBackgroundStyle(.color($0)) }
                    ),
                    supportsOpacity: false
                )

                HStack {
                    Spacer()
                    Button("Klart") { showColorPicker = false }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(minWidth: 320, minHeight: 280)
        }
    }

    private static let presetColors: [Color] = [
        .white, .black, .gray, .red, .orange, .yellow,
        .green, .mint, .teal, .blue, .purple, .pink,
    ]

    private func isSelectedColor(_ color: Color) -> Bool {
        if case .color(let current) = viewModel.backgroundStyle { return current == color }
        return false
    }

    private var previewAspectRatio: CGFloat {
        guard let size = viewModel.originalImage?.size, size.width > 0, size.height > 0 else { return 1 }
        return size.width / size.height
    }

    /// Sant om något finns att återställa - annars är "Återställ" bara en
    /// förvirrande knapp som inte gör något.
    private var hasChanges: Bool {
        viewModel.processedImage != nil
            || viewModel.compositedImage != nil
            || viewModel.outputShapeTransform != .identity
            || viewModel.backgroundStyle != .transparent
            || viewModel.outputShape != .square
            || viewModel.photoFilter != .none
            || viewModel.imageAdjustments != .identity
    }

    private var hasCustomBackground: Bool {
        if case .custom = viewModel.backgroundStyle { return true }
        return false
    }

    // Hero (20%) - EN av bara TVÅ hero-kontroller i hela appen, tillsammans
    // med export-klustret (`exportCluster`). Principen (skärpt 2026-09-26
    // efter att den ursprungliga listan - Bakgrund+Finjustera+Export - visade
    // sig sakna en riktig motivering): appens egen enderadsbeskrivning i
    // `CLAUDE.md` säger vad kärnlöftet ÄR - "ta bort/byta bakgrund... och
    // spara resultatet" - så BARA de två stegen (byta bakgrund, få ut
    // resultatet) får hero-behandling. Form/Filter/Justera/Motiv/Finjustera
    // är alla stödjande FINJUSTERINGAR inom det flödet, inte löftet i sig,
    // och förblir därför native oavsett hur "viktiga" de känns i
    // användningen.
    //
    // Se `ToolbarChrome.swift`s dokumentationskommentar för varför ett
    // `Menu` (som inte är en `Button`) använder `ToolbarChrome` direkt som
    // sitt `label:`-innehåll istället för `.buttonStyle(_:)`.
    private var backgroundMenu: some View {
        Menu {
            Button {
                viewModel.setBackgroundStyle(.transparent)
            } label: {
                Label("Ingen (genomskinlig)", systemImage: "checkerboard.rectangle")
            }

            Button {
                viewModel.setBackgroundStyle(.blurredOriginal)
            } label: {
                Label("Oskärpa av originalet", systemImage: "drop.fill")
            }

            Button {
                showColorPicker = true
            } label: {
                Label("Färg…", systemImage: "paintpalette")
            }

            Button {
                showBackgroundImporter = true
            } label: {
                Label("Egen bild…", systemImage: "photo")
            }

            if hasCustomBackground {
                Button {
                    viewModel.beginRepositioningCustomBackground()
                } label: {
                    Label("Justera position…", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                }
            }
        } label: {
            ToolbarChrome(tier: .hero) {
                HStack(spacing: 6) {
                    Image(systemName: "photo.fill")
                    Text("Bakgrund")
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .opacity(0.85)
                }
            }
        }
        .disabled(viewModel.originalImage == nil)
    }

    /// Det ihopslagna Spara+Dela-hero-klustret (20%) - EN pill med två
    /// segment, avdelade av en tunn linje, istället för två separata
    /// knappar - matchar "Export" som EN samlad, designad nyckel-action i
    /// mockupen, inte två likvärdiga verktygsknappar.
    private var exportCluster: some View {
        HStack(spacing: 0) {
            Button {
                viewModel.save()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down.fill")
                    Text("Spara")
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
            }
            .buttonStyle(.heroSegment)
            .disabled(viewModel.originalImage == nil)

            Rectangle()
                .fill(AppTheme.onAccent.opacity(0.35))
                .frame(width: 1, height: 16)

            if let shareURL = viewModel.shareURL {
                ShareLink(item: shareURL) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up.fill")
                        Text("Dela")
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.heroSegment)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up.fill")
                    Text("Dela")
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .opacity(0.5)
            }
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(AppTheme.onAccent)
        .background(Capsule(style: .continuous).fill(AppTheme.accent))
        .shadow(color: AppTheme.accent.opacity(0.3), radius: 6, y: 2)
    }

    private var shapeMenu: some View {
        Menu {
            ForEach(OutputShape.allCases) { shape in
                Button {
                    viewModel.setOutputShape(shape)
                } label: {
                    Label(shape.label, systemImage: shape.systemImage)
                }
            }
        } label: {
            ToolbarChrome(tier: .native) {
                Label("Form", systemImage: "square.on.circle")
            }
        }
        .disabled(viewModel.originalImage == nil)
    }

    /// Filformat för "Spara"/"Dela" (PNG med genomskinlighet, eller JPEG för
    /// mindre filstorlek) - påverkar båda knapparna direkt, precis som
    /// bakgrunds-/formvalen ovan.
    private var formatMenu: some View {
        Menu {
            ForEach(ImageExportFormat.allCases) { format in
                Button {
                    viewModel.setExportFormat(format)
                } label: {
                    Label(format.label, systemImage: format == viewModel.exportFormat ? "checkmark" : "circle")
                }
            }
        } label: {
            ToolbarChrome(tier: .native) {
                Label("Format", systemImage: "gearshape")
            }
        }
        .disabled(viewModel.originalImage == nil)
    }
}

/// Motivets ramning: dra/zooma/vrida är verksamt direkt när bilden laddats
/// in, inte gated bakom att välja bort bakgrund/byta bakgrund - se
/// `SearchViewModel.outputShape`s standardvärde (`.square`, inte
/// `.rectangle`) för varför det alltid finns en ram att positionera inom
/// från start.
private struct SubjectFramingCanvas: View {
    let image: PlatformImage
    let shape: OutputShape
    let aspectRatio: CGFloat
    @Binding var transform: CanvasTransform
    let onCommit: () -> Void

    var body: some View {
        ManipulableImageView(image: image, clipShape: shape.swiftUIShape, transform: $transform, onCommit: onCommit)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .background(CheckerboardBackground())
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct CheckerboardBackground: View {
    var body: some View {
        Canvas { context, size in
            let tile: CGFloat = 12
            var y: CGFloat = 0
            var rowEven = false
            while y < size.height {
                var x: CGFloat = 0
                var isDark = rowEven
                while x < size.width {
                    context.fill(
                        Path(CGRect(x: x, y: y, width: tile, height: tile)),
                        with: .color(isDark ? Color.gray.opacity(0.25) : Color.gray.opacity(0.1))
                    )
                    isDark.toggle()
                    x += tile
                }
                rowEven.toggle()
                y += tile
            }
        }
    }
}
