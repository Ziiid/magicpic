import SwiftUI
import UniformTypeIdentifiers

struct DetailPanel: View {
    @ObservedObject var viewModel: SearchViewModel
    @State private var showBackgroundImporter = false
    @State private var showAdjustments = false
    @State private var showEffects = false
    @State private var showPresets = false
    @State private var showPhotoFilters = false
    @State private var showBackgroundStylePicker = false
    @State private var showShapePicker = false
    @State private var showFreeformDrawer = false
    // Sant medan "visa original"-knappen hålls nedtryckt.
    @State private var showsOriginal = false
    @State private var showTextEditor = false
    @State private var showLogoImporter = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isCompact: Bool { horizontalSizeClass == .compact }
    #else
    private var isCompact: Bool { false }
    #endif

    // `body` är uppdelad i tre kedjor (innehåll → händelsehanterare →
    // sheets) - EN enda kedja med ~20 modifierare (sju sheets, fem
    // `onChange`, två `fileImporter`) blev för tung för typkontrollen
    // ("unable to type-check this expression in reasonable time").
    var body: some View {
        sheetedContent
            .overlay(alignment: .top) {
                if let message = viewModel.saveConfirmation {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AppTheme.onAccent)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule(style: .continuous).fill(AppTheme.accent))
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: viewModel.saveConfirmation)
            .sheet(isPresented: $showBackgroundStylePicker) {
                backgroundStyleSheet
            }
            .sheet(isPresented: $showShapePicker) {
                shapeSheet
            }
            .sheet(isPresented: $showFreeformDrawer) {
                freeformSheet
            }
    }

    /// Förklarar VARFÖR form/positionering inte går att ändra medan en
    /// ram-/remsstil (Polaroid, Fotoautomat) är vald - se `isLayoutStyle`.
    private var layoutStyleNotice: some View {
        Label(L("Polaroid och Fotoautomat bygger sin egen ram, så form och position kan inte ändras medan de är valda. Välj Ingen eller ett annat filter för att ändra dem."), systemImage: "info.circle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal)
    }

    /// Själva förhandsvisningen (laddar/layoutvisning/ramningsyta). På
    /// iPhone fyller den ytan under rubriken direkt; på bredare skärmar ligger
    /// den i en `ScrollView`.
    @ViewBuilder
    private var previewContent: some View {
        if viewModel.isLoadingDetail {
            ProgressView(L("Laddar bild…"))
                .padding(40)
        } else if viewModel.photoFilter.isLayoutStyle, viewModel.compositedImage == nil,
                  let preview = viewModel.adjustedPreviewImage {
            // Polaroid/Fotoautomat FÖRE bakgrundsborttagning körts -
            // `adjustedPreviewImage` är då redan HELA den inramade/
            // staplade bilden (se `PhotoFilterService.apply`), inte
            // bara motivet - visa den oklippt i sitt EGNA
            // bildförhållande istället för att tvinga in den i den
            // kvadrat-/formklippande `SubjectFramingCanvas` nedan
            // (en hög, smal fotoautomat-remsa blev annars beskuren
            // till bara mitten av remsan, rapporterat 2026-09-26).
            // Ingen drag-/nyp-ramning här - det finns inget att
            // positionera, ramen/remsan ÄR redan slutresultatet.
            Image(platformImage: preview)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding()
        } else if let original = viewModel.originalImage {
            // Alltid den inbäddade, dra-/nyp-/vridbara ramningsytan -
            // inget separat "justera position"-läge att växla till.
            // Källan är motivets GENOMSKINLIGA urklipp när det finns
            // (`subjectCutoutImage`), annars det obehandlade
            // originalet - INTE `compositedImage` (som har vald
            // bakgrund bakad in över hela originalets rektangel).
            // `SubjectFramingCanvas` ritar istället vald bakgrund
            // som ett eget, FAST lager bakom urklippet, så bakgrunden
            // fyller hela kanvasen oavsett var urklippet panorerats -
            // se `SearchViewModel.applyPipeline`s och
            // `subjectCutoutImage`s dokumentation, samt `buggs.md`.
            VStack(spacing: 8) {
                SubjectFramingCanvas(
                    image: viewModel.subjectCutoutImage ?? viewModel.adjustedPreviewImage ?? original,
                    shape: viewModel.shapePreset.silhouetteShape,
                    aspectRatio: viewModel.shapePreset.aspectRatio ?? previewAspectRatio,
                    backgroundStyle: viewModel.backgroundStyle,
                    originalImage: original,
                    transform: $viewModel.outputShapeTransform,
                    textOverlay: $viewModel.textOverlay,
                    logoOverlay: $viewModel.logoOverlay,
                    onCommit: { viewModel.commitOutputShapeTransform() },
                    onOverlayCommit: { viewModel.commitOverlays() },
                    onTextEdit: { if !showTextEditor { showTextEditor = true } },
                    onTextDelete: {
                        viewModel.textOverlay = nil
                        viewModel.commitOverlays()
                    },
                    onLogoDelete: { viewModel.removeLogo() }
                )
                .padding()
                // Håll "visa original"-knappen nedtryckt: originalet
                // läggs OVANPÅ (canvasen finns kvar under, så
                // markering/ramning inte nollställs).
                .overlay {
                    if showsOriginal {
                        ZStack(alignment: .top) {
                            Rectangle().fill(.background)
                            Image(platformImage: original)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding()
                            Text(L("Original"))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(.thinMaterial))
                                .padding(.top, 8)
                        }
                        .allowsHitTesting(false)
                    }
                }
            }
        } else {
            Text(L("Kunde inte ladda bilden."))
                .foregroundStyle(.secondary)
                .padding(40)
        }
    
    }

    private var baseContent: some View {
        VStack(spacing: 12) {
            // Hjälptexten ligger FAST ovanför ramningsytan (utanför
            // `ScrollView`) - under bilden hamnade den utom synhåll för
            // höga former som rektangel (rapporterat 2026-10-10).
            if showsFramingCanvas {
                // Inte på iPhone - där behöver bilden all höjd (introduktionen
                // förklarar gesterna).
                if !isCompact {
                    Text(L("Dra för att flytta, nyp för att zooma, vrid med två fingrar för att rotera."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else if viewModel.photoFilter.isLayoutStyle, viewModel.originalImage != nil {
                layoutStyleNotice
            }

            if isCompact {
                previewContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    previewContent
                }
            }

            // Zoom-/rotationsknapparna ligger UTANFÖR `ScrollView` - annars
            // hamnar de under bilden och syns bara om man scrollar när
            // verktygsraderna nedanför tar mycket höjd (rapporterat efter att
            // Logo-knappen fick rad 2 att brytas till två rader).
            if showsFramingCanvas, !isCompact {
                HStack(spacing: 8) {
                    Button {
                        viewModel.zoomSubject(by: 1 / 1.15)
                    } label: {
                        Label(L("Zooma ut"), systemImage: "minus.magnifyingglass")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.nativeToolbar)
                    .help(L("Zooma ut"))

                    Button {
                        viewModel.zoomSubject(by: 1.15)
                    } label: {
                        Label(L("Zooma in"), systemImage: "plus.magnifyingglass")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.nativeToolbar)
                    .help(L("Zooma in"))

                    Button {
                        viewModel.rotateSubject(byDegrees: -SearchViewModel.rotationStepDegrees)
                    } label: {
                        Label(L("Vrid åt vänster"), systemImage: "rotate.left")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.nativeToolbar)
                    .help(L("Vrid åt vänster"))

                    Button {
                        viewModel.rotateSubject(byDegrees: SearchViewModel.rotationStepDegrees)
                    } label: {
                        Label(L("Vrid åt höger"), systemImage: "rotate.right")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.nativeToolbar)
                    .help(L("Vrid åt höger"))

                    Button {
                        viewModel.mirrorSubject()
                    } label: {
                        Label(L("Spegelvänd bilden"), systemImage: "flip.horizontal")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.nativeToolbar)
                    .help(L("Spegelvänd bilden"))

                    // Håll nedtryckt = jämför med originalet (före/efter).
                    ToolbarChrome(tier: .native) {
                        Label(L("Håll nedtryckt för att visa originalet"), systemImage: "eye")
                            .labelStyle(.iconOnly)
                    }
                    .opacity(hasChanges ? 1 : 0.4)
                    .onLongPressGesture(minimumDuration: 0, maximumDistance: 80, pressing: { pressing in
                        showsOriginal = pressing && hasChanges
                    }, perform: {})
                    .help(L("Håll nedtryckt för att visa originalet"))

                    // Dra den färdiga bilden som en fil till Finder/annan app.
                    // Egen handtagsyta - att dra i själva bilden panorerar den.
                    if let shareURL = viewModel.shareURL {
                        ToolbarChrome(tier: .native) {
                            Label(L("Dra ut"), systemImage: "arrow.up.forward.square")
                        }
                        .fixedSize()
                        .onDrag { NSItemProvider(contentsOf: shareURL) ?? NSItemProvider() }
                        .help(L("Dra hit-ifrån till Finder eller en annan app för att släppa bilden som en fil."))
                    }
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
                    Text(L("Bearbetar…"))
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
            toolbar
                .padding(.horizontal, 2)
                .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity)
    }

    /// Mac/iPad (bred panel): tre rader med textknappar.
    private var regularToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Rad 1: Historik.
            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                Button {
                    viewModel.undo()
                } label: {
                    Label(L("Ångra"), systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(.nativeToolbar)
                .disabled(!viewModel.canUndo)
                .help(L("Ångra senaste ändringen."))

                Button {
                    viewModel.redo()
                } label: {
                    Label(L("Gör om"), systemImage: "arrow.uturn.forward")
                }
                .buttonStyle(.nativeToolbar)
                .disabled(!viewModel.canRedo)
                .help(L("Gör om den senast ångrade ändringen."))

                Button {
                    viewModel.restoreOriginal()
                } label: {
                    Label(L("Återställ till original"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.nativeToolbar)
                .disabled(!hasChanges)
                .help(L("Kasta bakgrunds-/form-/positioneringsval och gå tillbaka till originalbilden."))
            }

            // Rad 2: Redigeringsverktyg. Ingen egen "Ta bort bakgrund"-
            // knapp - "Ingen (genomskinlig)" under Bakgrund-menyn gör
            // exakt samma sak, en egen knapp för det var bara en
            // dubblett (rapporterat 2026-09-25).
            FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                Button {
                    showPresets = true
                } label: {
                    Label(L("Förval"), systemImage: "wand.and.stars")
                }
                .buttonStyle(.nativeToolbar)
                .disabled(viewModel.originalImage == nil)
                .help(L("Ett tryck sätter bakgrund, form och effekter."))

                backgroundMenu

                shapeMenu

                Button {
                    showPhotoFilters = true
                } label: {
                    Label(L("Filter"), systemImage: "camera.filters")
                }
                .buttonStyle(.nativeToolbar)
                .disabled(viewModel.originalImage == nil)
                .help(L("Färdiga bildstilar - svartvitt, sepia, röntgen, m.fl."))

                Button {
                    showAdjustments = true
                } label: {
                    Label(L("Justera"), systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.nativeToolbar)
                .disabled(viewModel.originalImage == nil)
                .help(L("Ljusstyrka, kontrast, mättnad, skärpa, temperatur, highlights/shadows, brusreducering, vinjett."))

                Button {
                    showEffects = true
                } label: {
                    Label(L("Effekter"), systemImage: "sparkles")
                }
                .buttonStyle(.nativeToolbar)
                .disabled(viewModel.originalImage == nil)
                .help(L("Skugga och kontur på motivet."))

                // Native, INTE hero - penseln KORRIGERAR vad Vision
                // missade, den är inte appens primära löfte (det är
                // Bakgrund + Exportera, se motiveringen vid
                // `backgroundMenu`).
                Button {
                    viewModel.beginMaskEditing()
                } label: {
                    Label(L("Finjustera"), systemImage: "paintbrush")
                }
                .buttonStyle(.nativeToolbar)
                .disabled(viewModel.processedImage == nil)
                .help(L("Måla för hand för att lägga till eller ta bort delar av urklippet."))
                if viewModel.hasMultipleSubjects {
                    Button {
                        viewModel.reopenSubjectPicker()
                    } label: {
                        Label(L("Motiv…"), systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.nativeToolbar)
                    .help(L("Välj om vilket eller vilka motiv som ska behållas."))
                }
            }

            // Rad 3: Lägg till text/logotyp och Utdata - Spara/Dela
            // högerställda, allt annat till vänster.
            HStack(alignment: .top, spacing: 8) {
                FlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    Button {
                        viewModel.ensureTextOverlay()
                        showTextEditor = true
                    } label: {
                        Label(L("Text"), systemImage: "textformat")
                    }
                    .buttonStyle(.nativeToolbar)
                    .disabled(viewModel.originalImage == nil)
                    .help(L("Lägg till en text som du kan flytta, ändra storlek på och vrida."))

                    Button {
                        showLogoImporter = true
                    } label: {
                        Label(L("Logo"), systemImage: "photo.badge.plus")
                    }
                    .buttonStyle(.nativeToolbar)
                    .disabled(viewModel.originalImage == nil)
                    .help(L("Lägg på en logotyp eller bild som du kan flytta, ändra storlek på, vrida och spegelvända."))

                    formatMenu
                }
                Spacer(minLength: 8)
                exportCluster()
            }
        }
    }

    /// Välj verktygslayout efter tillgänglig bredd: iPhone (och smal iPad-
    /// vy) får `compactToolbar`, allt annat den breda raden ovan. Samma
    /// vy och samma åtgärder - bara presentationen skiljer.
    @ViewBuilder
    private var toolbar: some View {
        if isCompact {
            compactToolbar
        } else {
            regularToolbar
        }
    }

    /// iPhone: ALLT som ikoner (ingen text under knapparna) för att ge
    /// bilden så mycket höjd som möjligt - en rad med historik + vy
    /// (zooma/vrid/spegla/jämför), ett rutnät med verktyg i fem kolumner,
    /// och Spara/Dela som en fullbredds hero-rad längst ner.
    private var compactToolbar: some View {
        VStack(spacing: 8) {
            compactActionRow

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                compactToolButton(L("Förval"), systemImage: "wand.and.stars", disabled: viewModel.originalImage == nil) {
                    showPresets = true
                }
                compactToolButton(L("Bakgrund"), systemImage: "photo.fill", disabled: viewModel.originalImage == nil) {
                    showBackgroundStylePicker = true
                }
                compactToolButton(L("Form"), systemImage: "square.on.circle", disabled: viewModel.originalImage == nil) {
                    showShapePicker = true
                }
                compactToolButton(L("Filter"), systemImage: "camera.filters", disabled: viewModel.originalImage == nil) {
                    showPhotoFilters = true
                }
                compactToolButton(L("Justera"), systemImage: "slider.horizontal.3", disabled: viewModel.originalImage == nil) {
                    showAdjustments = true
                }
                compactToolButton(L("Effekter"), systemImage: "sparkles", disabled: viewModel.originalImage == nil) {
                    showEffects = true
                }
                compactToolButton(L("Finjustera"), systemImage: "paintbrush", disabled: viewModel.processedImage == nil) {
                    viewModel.beginMaskEditing()
                }
                if viewModel.hasMultipleSubjects {
                    compactToolButton(L("Motiv…"), systemImage: "checkmark.circle") {
                        viewModel.reopenSubjectPicker()
                    }
                }
                compactToolButton(L("Text"), systemImage: "textformat", disabled: viewModel.originalImage == nil) {
                    viewModel.ensureTextOverlay()
                    showTextEditor = true
                }
                compactToolButton(L("Logo"), systemImage: "photo.badge.plus", disabled: viewModel.originalImage == nil) {
                    showLogoImporter = true
                }
                Menu {
                    formatMenuItems
                } label: {
                    compactToolLabel(L("Format"), systemImage: "gearshape")
                }
                .tint(.primary)
                .disabled(viewModel.originalImage == nil)
                .opacity(viewModel.originalImage == nil ? 0.4 : 1)
            }

            exportCluster(expands: true)
        }
    }

    /// Historik (ångra/gör om/återställ) och vy (zooma/vrid/spegla/jämför)
    /// i EN rad av små ikonknappar.
    private var compactActionRow: some View {
        HStack(spacing: 4) {
            compactIconButton(L("Ångra"), systemImage: "arrow.uturn.backward", disabled: !viewModel.canUndo) {
                viewModel.undo()
            }
            compactIconButton(L("Gör om"), systemImage: "arrow.uturn.forward", disabled: !viewModel.canRedo) {
                viewModel.redo()
            }
            compactIconButton(L("Återställ till original"), systemImage: "arrow.counterclockwise", disabled: !hasChanges) {
                viewModel.restoreOriginal()
            }

            if showsFramingCanvas {
                Divider().frame(height: 22)

                compactIconButton(L("Zooma ut"), systemImage: "minus.magnifyingglass") {
                    viewModel.zoomSubject(by: 1 / 1.15)
                }
                compactIconButton(L("Zooma in"), systemImage: "plus.magnifyingglass") {
                    viewModel.zoomSubject(by: 1.15)
                }
                compactIconButton(L("Vrid åt vänster"), systemImage: "rotate.left") {
                    viewModel.rotateSubject(byDegrees: -SearchViewModel.rotationStepDegrees)
                }
                compactIconButton(L("Vrid åt höger"), systemImage: "rotate.right") {
                    viewModel.rotateSubject(byDegrees: SearchViewModel.rotationStepDegrees)
                }
                compactIconButton(L("Spegelvänd bilden"), systemImage: "flip.horizontal") {
                    viewModel.mirrorSubject()
                }

                // Håll nedtryckt = jämför med originalet.
                Image(systemName: "eye")
                    .font(.system(size: 16))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                    .opacity(hasChanges ? 1 : 0.4)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0, maximumDistance: 80, pressing: { pressing in
                        showsOriginal = pressing && hasChanges
                    }, perform: {})
                    .accessibilityLabel(L("Håll nedtryckt för att visa originalet"))
            }
        }
    }

    private func compactIconButton(
        _ title: String,
        systemImage: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16))
                .frame(maxWidth: .infinity, minHeight: 40)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
        .accessibilityLabel(title)
    }

    private func compactToolButton(
        _ title: String,
        systemImage: String,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            compactToolLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }

    private func compactToolLabel(_ title: String, systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 20))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .accessibilityLabel(title)
    }

    private var handledContent: some View {
        baseContent
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
        // Motivväljaren kan dyka upp MEDAN t.ex. Bakgrund-/Form-väljaren
        // fortfarande är öppen (de ligger kvar öppna efter ett val), och
        // SwiftUI visar bara EN sheet i taget - den nya väntade då tyst
        // tills den gamla stängdes ("only presenting a single sheet is
        // supported"). Stäng de andra uttryckligen så väljaren kommer direkt.
        .onChange(of: viewModel.subjectSelectionRequest?.id) { _, id in
            guard id != nil else { return }
            showBackgroundStylePicker = false
            showShapePicker = false
            showPhotoFilters = false
            showAdjustments = false
            showEffects = false
            showPresets = false
            showTextEditor = false
        }
        .onChange(of: showTextEditor) { _, isPresented in
            if !isPresented {
                viewModel.commitOverlays()
            }
        }
        .sheet(isPresented: $showTextEditor) {
            if let overlayBinding = Binding($viewModel.textOverlay) {
                TextOverlayEditorView(
                    overlay: overlayBinding,
                    onDelete: {
                        viewModel.textOverlay = nil
                        showTextEditor = false
                    },
                    onDone: { showTextEditor = false }
                )
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
        .fileImporter(isPresented: $showLogoImporter, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                Task { await viewModel.setLogo(from: url) }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private var sheetedContent: some View {
        handledContent
        .sheet(item: $viewModel.backgroundPositioningRequest) { request in
            ImagePositionerView(
                title: L("Justera bakgrundsbilden"),
                subtitle: L("Dra för att flytta, nyp för att zooma, vrid med två fingrar för att rotera."),
                image: request.image,
                previewAspectRatio: previewAspectRatio,
                clipShape: AnyShape(Rectangle()),
                doneLabel: L("Använd bakgrund"),
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
                    onDone: { showPhotoFilters = false },
                    loadPreviewMask: { await viewModel.previewMask() }
                )
            }
        }
        .sheet(isPresented: $showPresets) {
            QuickPresetsView(
                onSelect: { preset in
                    showPresets = false
                    viewModel.applyQuickPreset(preset)
                },
                onDone: { showPresets = false }
            )
        }
        .sheet(isPresented: $showEffects) {
            SubjectEffectsView(
                previewImage: viewModel.subjectCutoutImage ?? viewModel.adjustedPreviewImage ?? viewModel.originalImage,
                initial: viewModel.subjectEffects,
                onChange: { viewModel.setSubjectEffects($0) },
                onDone: { showEffects = false }
            )
        }
        .sheet(isPresented: $showAdjustments) {
            ImageAdjustmentsView(
                adjustments: viewModel.imageAdjustments,
                previewImage: viewModel.livePreviewImage ?? viewModel.adjustedPreviewImage ?? viewModel.originalImage,
                onChange: { adjustments, commit in
                    if commit {
                        viewModel.setImageAdjustments(adjustments)
                    } else {
                        viewModel.previewImageAdjustments(adjustments)
                    }
                },
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
    }

    @ViewBuilder private var backgroundStyleSheet: some View {
        if let original = viewModel.originalImage {
            BackgroundStylePickerView(
                baseImage: original,
                currentStyle: viewModel.backgroundStyle,
                hasCustomBackground: hasCustomBackground,
                onSelect: { viewModel.setBackgroundStyle($0) },
                onPickCustomImage: {
                    showBackgroundStylePicker = false
                    showBackgroundImporter = true
                },
                onRepositionCustomImage: {
                    showBackgroundStylePicker = false
                    viewModel.beginRepositioningCustomBackground()
                },
                onDone: { showBackgroundStylePicker = false },
                loadPreviewMask: { await viewModel.previewMask() }
            )
        }
    }

    @ViewBuilder private var shapeSheet: some View {
        if let original = viewModel.originalImage {
            ShapePickerView(
                baseImage: viewModel.compositedImage ?? viewModel.adjustedPreviewImage ?? original,
                transform: viewModel.outputShapeTransform,
                currentPreset: viewModel.shapePreset,
                isLayoutFilterActive: viewModel.photoFilter.isLayoutStyle,
                onSelect: { preset in
                    if preset.contour == .freeform {
                        // Frihand: rita först konturen i egen ruta.
                        showShapePicker = false
                        showFreeformDrawer = true
                    } else {
                        viewModel.setShapePreset(preset)
                    }
                },
                onDone: { showShapePicker = false }
            )
        }
    }

    @ViewBuilder private var freeformSheet: some View {
        if let original = viewModel.originalImage {
            FreeformDrawView(
                baseImage: viewModel.compositedImage ?? viewModel.adjustedPreviewImage ?? original,
                onDone: { path in
                    showFreeformDrawer = false
                    viewModel.setShapePreset(.freeform(path))
                },
                onCancel: { showFreeformDrawer = false }
            )
        }
    }

    /// Sant när `SubjectFramingCanvas` visas (samma villkor som i `ScrollView`s
    /// grenar ovan) - då hör zoom-/rotationsknapparna hemma under den.
    private var showsFramingCanvas: Bool {
        guard viewModel.originalImage != nil, !viewModel.isLoadingDetail else { return false }
        let showsLayoutPreview = viewModel.photoFilter.isLayoutStyle
            && viewModel.compositedImage == nil
            && viewModel.adjustedPreviewImage != nil
        return !showsLayoutPreview
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
            || viewModel.shapePreset != .square
            || viewModel.photoFilter != .none
            || viewModel.textOverlay != nil
            || viewModel.logoOverlay != nil
            || viewModel.imageAdjustments != .identity
    }

    private var hasCustomBackground: Bool {
        if case .custom = viewModel.backgroundStyle { return true }
        return false
    }

    // Native, INTE hero - ändrat 2026-09-26 på uttrycklig begäran (användaren
    // ville BARA ha Spara/Dela gröna, allt annat inklusive Bakgrund ska se
    // ut som Filter/Justera). Den tidigare motiveringen (Bakgrund ansågs
    // vara hälften av appens kärnlöfte, "ta bort/byta bakgrund... och spara
    // resultatet") är alltså överspelad - se `CLAUDE.md`s "Verktygsradens
    // knappar"-avsnitt för den uppdaterade regeln. `exportCluster` är nu den
    // ENDA hero-kontrollen i appen.
    //
    // Öppnar `BackgroundStylePickerView` (riktiga förhandsgranskningar,
    // rapporterat 2026-09-26 att Bakgrund/Form saknade det Filter redan
    // hade) istället för en textmeny.
    private var backgroundMenu: some View {
        Button {
            showBackgroundStylePicker = true
        } label: {
            Label(L("Bakgrund"), systemImage: "photo.fill")
        }
        .buttonStyle(.nativeToolbar)
        .disabled(viewModel.originalImage == nil)
    }

    /// Spara + Dela - två SEPARATA hero-piller bredvid varandra (inte en
    /// ihopslagen pill, det läste som EN knapp, rapporterat 2026-09-29).
    private func exportCluster(expands: Bool = false) -> some View {
        HStack(spacing: 8) {
            Button {
                viewModel.save()
            } label: {
                exportLabel(L("Spara"), systemImage: "square.and.arrow.down.fill", expands: expands)
            }
            .buttonStyle(.heroSegment)
            .disabled(viewModel.originalImage == nil)

            if let shareURL = viewModel.shareURL {
                ShareLink(item: shareURL) {
                    exportLabel(L("Dela"), systemImage: "square.and.arrow.up.fill", expands: expands)
                }
                .buttonStyle(.heroSegment)
            } else {
                exportLabel(L("Dela"), systemImage: "square.and.arrow.up.fill", expands: expands)
                    .opacity(0.5)
            }
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(AppTheme.onAccent)
        .frame(maxWidth: expands ? .infinity : nil)
    }

    private func exportLabel(_ title: String, systemImage: String, expands: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 7)
        .frame(maxWidth: expands ? .infinity : nil)
        .background(Capsule(style: .continuous).fill(AppTheme.accent))
        .shadow(color: AppTheme.accent.opacity(0.3), radius: 6, y: 2)
    }

    // Öppnar `ShapePickerView` (riktiga förhandsgranskningar) istället för
    // en textmeny - samma anledning som `backgroundMenu` ovan. Skickar bara
    // `Label` som `label:` och sätter `.buttonStyle(.nativeToolbar)` - EXAKT
    // samma mönster som Ångra/Filter/Justera - istället för att manuellt
    // slå in en `ToolbarChrome` (se buggs.md 2026-09-26, "Blå text kvarstod
    // på Form/Format" för varför den skillnaden faktiskt spelar roll).
    private var shapeMenu: some View {
        Button {
            showShapePicker = true
        } label: {
            Label(L("Form"), systemImage: "square.on.circle")
        }
        .buttonStyle(.nativeToolbar)
        .disabled(viewModel.originalImage == nil)
    }

    /// Filformat för "Spara"/"Dela" (PNG med genomskinlighet, eller JPEG för
    /// mindre filstorlek) - påverkar båda knapparna direkt, precis som
    /// bakgrunds-/formvalen ovan. Måste förbli ett riktigt `Menu` (den
    /// nedrullningsbara listan går inte att bygga med `.buttonStyle`), så
    /// `.tint(.primary)` sätts uttryckligen på SJÄLVA `Menu`-vyn (inte bara i
    /// dess `label:`-innehåll) för att neutralisera systemets accentfärg på
    /// kontrollens egen krom - se buggs.md 2026-09-26.
    @ViewBuilder
    private var formatMenuItems: some View {
        Section(L("Filformat")) {
            ForEach(ImageExportFormat.allCases) { format in
                Button {
                    viewModel.setExportFormat(format)
                } label: {
                    Label(format.label, systemImage: format == viewModel.exportFormat ? "checkmark" : "circle")
                }
            }
        }
        Section(L("Storlek")) {
            ForEach(ExportSize.allCases) { size in
                Button {
                    viewModel.setExportSize(size)
                } label: {
                    Label(size.label, systemImage: size == viewModel.exportSize ? "checkmark" : "circle")
                }
            }
        }
    }

    private var formatMenu: some View {
        Menu {
            formatMenuItems
        } label: {
            ToolbarChrome(tier: .native) {
                Label(L("Format"), systemImage: "gearshape")
            }
        }
        .tint(.primary)
        .disabled(viewModel.originalImage == nil)
    }
}

/// Motivets ramning: dra/zooma/vrida är verksamt direkt när bilden laddats
/// in, inte gated bakom att välja bort bakgrund/byta bakgrund - se
/// `SearchViewModel.shapePreset`s standardvärde (`.square`, inte
/// `.rectangle`) för varför det alltid finns en ram att positionera inom
/// från start.
private struct SubjectFramingCanvas: View {
    let image: PlatformImage
    let shape: AnyShape
    let aspectRatio: CGFloat
    let backgroundStyle: BackgroundOption
    let originalImage: PlatformImage
    @Binding var transform: CanvasTransform
    @Binding var textOverlay: TextOverlay?
    @Binding var logoOverlay: LogoOverlay?
    let onCommit: () -> Void
    let onOverlayCommit: () -> Void
    let onTextEdit: () -> Void
    let onTextDelete: () -> Void
    let onLogoDelete: () -> Void

    private enum SelectedOverlay { case text, logo }
    // Vilket lager (text/logotyp) som är markerat (grön ram med handtag) -
    // högst ett åt gången. Ett nytt lager markeras direkt (se `onChange`).
    @State private var selected: SelectedOverlay? = .text

    private func isSelected(_ kind: SelectedOverlay) -> Binding<Bool> {
        Binding(
            get: { selected == kind },
            set: { newValue in
                if newValue {
                    selected = kind
                } else if selected == kind {
                    selected = nil
                }
            }
        )
    }

    var body: some View {
        ManipulableImageView(image: image, clipShape: shape, transform: $transform, onCommit: onCommit, allowsExposedEdges: true)
            // Ett tryck utanför texten avmarkerar den (texten själv tar
            // sina egna tryck, se `TextOverlayLayer`).
            // `simultaneousGesture` (inte `onTapGesture`) så tryckigenkänningen
            // aldrig kan fördröja/blockera dra-/nyp-/vridgesten på motivet.
            .simultaneousGesture(TapGesture().onEnded { selected = nil })
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    overlayLayers(containerSize: geo.size)
                }
            }
            .onChange(of: textOverlay != nil) { _, isPresent in
                if isPresent { selected = .text }
            }
            .onChange(of: logoOverlay != nil) { _, isPresent in
                if isPresent { selected = .logo }
            }
            // Bakgrunden klipps till formens siluett (som i exporten) - annars
            // syns bakgrundsfärgen utanför t.ex. en åttahörning/cirkel.
            .background(backgroundLayer.clipShape(shape))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// Logotypen under texten (standard) eller över den (`isInFront`) -
    /// samma ordning som i exporten. Lagerknappen visas bara när BÅDA
    /// finns; sist i `ZStack` = överst.
    @ViewBuilder
    private func overlayLayers(containerSize: CGSize) -> some View {
        let hasBoth = logoOverlay != nil && textOverlay != nil
        let logoInFront = logoOverlay?.isInFront == true
        ZStack {
            if logoInFront { textLayer(containerSize: containerSize, hasBoth: hasBoth) }
            if let logoBinding = Binding($logoOverlay) {
                LogoOverlayLayer(
                    logo: logoBinding,
                    isSelected: isSelected(.logo),
                    containerSize: containerSize,
                    onCommit: onOverlayCommit,
                    onDelete: onLogoDelete,
                    onBringToFront: hasBoth ? { logoOverlay?.isInFront = true; onOverlayCommit() } : nil,
                    onSendBack: hasBoth ? { logoOverlay?.isInFront = false; onOverlayCommit() } : nil
                )
            }
            if !logoInFront { textLayer(containerSize: containerSize, hasBoth: hasBoth) }
        }
    }

    @ViewBuilder
    private func textLayer(containerSize: CGSize, hasBoth: Bool) -> some View {
        if let overlayBinding = Binding($textOverlay) {
            TextOverlayLayer(
                overlay: overlayBinding,
                isSelected: isSelected(.text),
                containerSize: containerSize,
                onCommit: onOverlayCommit,
                onEdit: onTextEdit,
                onDelete: onTextDelete,
                // Text "överst" = logotypen under (och tvärtom).
                onBringToFront: hasBoth ? { logoOverlay?.isInFront = false; onOverlayCommit() } : nil,
                onSendBack: hasBoth ? { logoOverlay?.isInFront = true; onOverlayCommit() } : nil
            )
        }
    }

    /// Ett FAST bakgrundslager bakom urklippet - flyttas ALDRIG av
    /// `transform` (till skillnad från `image` ovan), så vald bakgrund
    /// fyller hela kanvasen oavsett var motivet panorerats. Bara en
    /// förhandsvisning - `oskärpa`/`egen bild` approximeras med SwiftUIs
    /// egna, billiga verktyg (`.blur`/enkla transform-modifiers) istället
    /// för att köra CoreImage-pipelinen på varje ritad bildruta; den
    /// FAKTISKA exporten renderas alltid via `BackgroundRemovalService`
    /// (se `SearchViewModel.applyPipeline`), så den här approximationen
    /// påverkar bara hur förhandsvisningen ser ut medan man panorerar.
    @ViewBuilder
    private var backgroundLayer: some View {
        switch backgroundStyle {
        case .transparent:
            CheckerboardBackground()
        case .color(let color):
            color
        case .gradient(let preset):
            preset.linearGradient
        case .blurredOriginal:
            Image(platformImage: originalImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .blur(radius: 20)
        case .custom(let customImage, let bgTransform):
            GeometryReader { geo in
                let containerSize = geo.size
                Image(platformImage: customImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: containerSize.width, height: containerSize.height)
                    .scaleEffect(max(bgTransform.scale, CanvasTransform.minScale))
                    .rotationEffect(bgTransform.rotation)
                    .offset(x: bgTransform.offset.width * containerSize.width, y: bgTransform.offset.height * containerSize.height)
                    .frame(width: containerSize.width, height: containerSize.height)
                    .clipped()
            }
        }
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
