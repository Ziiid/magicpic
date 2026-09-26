import SwiftUI

@MainActor
public final class SearchViewModel: ObservableObject {
    @Published public var query: String = ""
    @Published public var sourceKind: ImageSourceKind = .web
    @Published public var searchEngine: WebSearchEngine = .google
    @Published public var errorMessage: String?

    @Published public var selectedItem: SearchResultItem?
    @Published public var originalImage: PlatformImage?
    // Motivet mot vald bakgrund, men INTE formbeskuret ännu (till skillnad
    // från `processedImage`) - källan för den inbäddade formramningen
    // (`SubjectFramingCanvas`), så man ser rätt bakgrund medan man
    // positionerar istället för det obehandlade originalet. Annars ser det
    // ut som att bakgrunden "kommer tillbaka" så fort man börjar justera
    // positionen (rapporterat 2026-09-25).
    @Published public var compositedImage: PlatformImage?
    @Published public var processedImage: PlatformImage?
    // Originalet med `photoFilter` + `imageAdjustments` tillämpade, men
    // INNAN Vision/bakgrund/form - ren, billig CoreImage-förhandsvisning
    // (ingen Vision-körning) så man ser effekten direkt, även innan man
    // någonsin bett om bakgrundsborttagning. Se `refreshEditPreview()`.
    @Published public var adjustedPreviewImage: PlatformImage?
    @Published public var isLoadingDetail = false
    @Published public var isProcessing = false
    @Published public var backgroundStyle: BackgroundOption = .transparent
    @Published public var photoFilter: PhotoFilter = .none
    @Published public var imageAdjustments: ImageAdjustments = .identity
    // Kvadrat, inte rektangel, är standard - annars finns ingen ram att
    // dra/zooma/vrida motivet inom direkt när bilden laddats in (se
    // `SubjectFramingCanvas` i DetailPanel.swift, verksam omedelbart, inte
    // gated bakom att välja bort bakgrund/byta bakgrund).
    @Published public var outputShape: OutputShape = .square
    @Published public var outputShapeTransform: CanvasTransform = .identity
    @Published public var backgroundPositioningRequest: BackgroundPositioningRequest?
    @Published public var maskEditingRequest: MaskEditingRequest?
    @Published public var subjectSelectionRequest: SubjectSelectionRequest?
    @Published public var exportFormat: ImageExportFormat = .png
    // En redan skriven temporär fil i valt format, redo att delas via
    // `ShareLink` (Meddelanden/Mail/AirDrop m.fl.) - se `refreshShareURL()`.
    // `nil` betyder "inget att dela än" (ingen bild inläst, eller kodningen
    // misslyckades) - `DetailPanel` döljer/inaktiverar då Dela-knappen.
    @Published public var shareURL: URL?
    // Styr om Ångra/Gör om-knapparna i `DetailPanel` är aktiva - se
    // undo/redo-historiken längst ner i filen.
    @Published public private(set) var canUndo: Bool = false
    @Published public private(set) var canRedo: Bool = false

    public struct BackgroundPositioningRequest: Identifiable {
        public let id = UUID()
        public let image: PlatformImage
        public let initialTransform: CanvasTransform
    }

    public struct MaskEditingRequest: Identifiable {
        public let id = UUID()
        public let baseImage: PlatformImage
        public let editableMask: EditableMask
    }

    /// Ett motiv redo att visas i motivväljaren: `overlayImage` är motivets
    /// FAKTISKA form (Visions egen mask för just den instansen) färglagd och
    /// halvgenomskinlig, förberäknad en gång så väljarvyn bara behöver rita
    /// upp den, inte köra CoreImage per rendering.
    public struct SubjectPickerInstance: Identifiable {
        public let id: Int
        public let boundingBox: CGRect
        public let overlayImage: PlatformImage
    }

    public struct SubjectSelectionRequest: Identifiable {
        public let id = UUID()
        public let baseImage: PlatformImage
        public let instances: [SubjectPickerInstance]
        public let initiallySelected: Set<Int>
    }

    /// Ett komplett "läge" för ALLA redigeringsval (bakgrund, form,
    /// positionering, filter, justeringar, motivval OCH den slutgiltiga
    /// masken - inklusive manuella pensel-redigeringar, eftersom de
    /// ersätter `cachedMask` direkt) - en punkt i undo/redo-historiken.
    /// Innehåller MEDVETET inte t.ex. `exportFormat` - det är ett
    /// spara-/dela-val, inte en redigering av själva bilden.
    private struct EditSnapshot: Equatable {
        let backgroundStyle: BackgroundOption
        let photoFilter: PhotoFilter
        let imageAdjustments: ImageAdjustments
        let outputShape: OutputShape
        let outputShapeTransform: CanvasTransform
        let selectedSubjectIDs: Set<Int>?
        let cachedMask: BackgroundRemovalService.ForegroundMask?
    }

    private let exporter: ImageExporter
    private let backgroundRemoval = BackgroundRemovalService()
    private let shapeCrop = ShapeCropService()
    private let imageAdjustment = ImageAdjustmentService()
    private let photoFilterService = PhotoFilterService()
    // Ökas för varje refreshEditPreview()-anrop så att en sen, ren
    // förhandsvisningskörning (utan Vision) inte skriver över en nyare -
    // samma mönster som `backgroundGeneration`.
    private var adjustmentGeneration = 0

    // Cachar den dyra Vision-masken per bild så att byte av bakgrundsstil
    // bara behöver köra om den billiga kompositeringen.
    private var cachedMask: BackgroundRemovalService.ForegroundMask?
    private var cachedMaskSource: PlatformImage?
    // Cachar Visions RÅA motivdetektering (alla separata instanser, innan
    // ett urval gjorts) separat från `cachedMask` (den FÄRDIGA, ihopslagna
    // masken för de valda instanserna) - så att att byta motivval om (via
    // `reopenSubjectPicker()`) eller att första gången slå ihop det
    // användaren valt inte kräver att Vision-analysen körs om, bara att
    // `combinedMask(selecting:from:)` anropas på nytt.
    private var cachedSubjects: BackgroundRemovalService.DetectedSubjects?
    private var cachedSubjectsSource: PlatformImage?
    // Cachar de förberäknade overlay-bilderna för motivväljaren (dyr
    // CoreImage-rendering per instans) så `reopenSubjectPicker()` kan visa
    // väljaren igen utan att rendera om dem.
    private var cachedPickerInstances: [SubjectPickerInstance]?
    // Vilka instanser användaren valt att behålla för aktuell bild - `nil`
    // betyder "inget val gjort än" (fler än ett motiv hittat, väljaren ska
    // visas). Nollställs bara när bilden byts (se `loadImportedImage`) -
    // INTE av `restoreOriginal()` eller av att bakgrund/form/filter byts,
    // så ett gjort motivval överlever precis som `cachedMask` gör.
    private var selectedSubjectIDs: Set<Int>?
    // Ökas för varje removeBackground()-anrop så att ett sent svar från ett
    // äldre anrop (t.ex. vid snabba klick i färgväljaren) inte skriver över
    // resultatet av ett nyare.
    private var backgroundGeneration = 0

    // Undo/redo-historik - se `EditSnapshot` ovan och `pushUndoSnapshot()`/
    // `undo()`/`redo()` längst ner. Ny ändring efter en ångring rensar
    // `redoStack`, precis som i alla andra undo/redo-implementationer.
    private var undoStack: [EditSnapshot] = []
    private var redoStack: [EditSnapshot] = []
    // Det SENAST committade värdet av `outputShapeTransform` - behövs för
    // `commitOutputShapeTransform()`, som (till skillnad från alla andra
    // "sätt X"-metoder) inte kan läsa "värdet innan ändringen" ur sig själv:
    // SwiftUIs bindning i `ManipulableImageView` har redan skrivit det NYA
    // värdet till `outputShapeTransform` INNAN `onCommit`/den här metoden
    // ens anropas. Uppdateras varje gång transformen sätts på något annat
    // sätt också (nollställning, undo/redo) så den aldrig blir inaktuell.
    private var lastCommittedTransform: CanvasTransform = .identity
    // Tillståndet precis INNAN en pågående "session" (Justera-panelen eller
    // Filter-väljaren öppen) - flera ändringar under sessionen (varje
    // reglageutslag/filtertryck) ska bli ETT enda undo-steg när sessionen
    // avslutas, inte ett steg VAR. `nil` = ingen session pågår just nu.
    private var editSessionSnapshot: EditSnapshot?

    public init(exporter: ImageExporter) {
        self.exporter = exporter
    }

    /// Bygger sökmotor-URL:en för den aktuella sökningen (`query` +
    /// `searchEngine`), att öppna i systemets webbläsare - appen hämtar
    /// inga sökresultat själv (ingen API-nyckel, inga stockbilds-
    /// begränsningar som med tidigare Unsplash-lösningen). Användaren
    /// hittar bilden i webbläsaren och drar sedan in den i appen precis
    /// som vilken webbild/fil som helst.
    public func webSearchURL() -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return searchEngine.searchURL(for: trimmed)
    }

    /// Färgen motiv-overlayerna målas med i motivväljaren - markerar VALDA
    /// motiv, alltså exakt "aktivt/valt" (se `AppTheme`s dokumentation) -
    /// appens enda accentfärg (`AppTheme.accentCGColor`), inte en egen blå
    /// ton. `CGColor` behövs (inte `Color`) eftersom overlayen renderas med
    /// CoreImage, inte SwiftUI.
    private static let subjectOverlayColor = AppTheme.accentCGColor

    public func removeBackground() {
        guard let original = originalImage else { return }
        errorMessage = nil

        // Snabbvägen: redan en färdig, ihopslagen mask för den här bilden
        // (samma bild - och om flera motiv fanns, samma motivval) - då
        // behöver varken Vision eller motivväljaren köras/visas igen, bara
        // den billiga kompositeringen (t.ex. vid byte av bakgrundsstil).
        if cachedMaskSource === original, let mask = cachedMask {
            isProcessing = true
            applyPipeline(mask: mask, original: original)
            return
        }

        isProcessing = true
        let reusableSubjects = (cachedSubjectsSource === original) ? cachedSubjects : nil
        let priorSelection = selectedSubjectIDs

        backgroundGeneration += 1
        let generation = backgroundGeneration

        Task.detached(priority: .userInitiated) { [backgroundRemoval] in
            do {
                // Motivdetekteringen (alla separata instanser) cachas mot
                // den OJUSTERADE originalbilden precis som masken - ett
                // filter/en bildkorrigering ändrar inte motivens konturer.
                let subjects = try reusableSubjects ?? backgroundRemoval.detectSubjects(in: original)

                #if DEBUG
                // Tillfällig diagnostik (samma mönster som `handleDrop`s
                // #if DEBUG-loggning i ContentView.swift) för att avgöra OM
                // Vision själv bara rapporterar ETT motiv för en bild med
                // flera personer (känd begränsning hos
                // VNGenerateForegroundInstanceMaskRequest - instanserna
                // separeras genom visuell särskiljbarhet, inte
                // person-medveten segmentering, så personer som står tätt
                // ihop/överlappar kan smälta samman till EN instans) -
                // istället för en bugg i själva väljar-flödet.
                print("[SubjectDetection] Vision hittade \(subjects.instances.count) motiv: \(subjects.instances.map { "#\($0.id) @ \($0.boundingBox)" })")
                #endif

                if subjects.instances.count > 1, priorSelection == nil {
                    // Flera motiv hittades och användaren har inte valt
                    // vilka som ska behållas än - pausa här och fråga,
                    // istället för att (som tidigare) tyst behålla alla.
                    // Om BARA ett motiv hittas hoppar koden ALDRIG hit -
                    // det befintliga flödet fortsätter direkt nedan, precis
                    // som innan motivväljaren fanns.
                    let pickerInstances = try subjects.instances.map { instance -> SubjectPickerInstance in
                        let overlay = try backgroundRemoval.colorizedOverlay(
                            for: instance.mask,
                            color: Self.subjectOverlayColor,
                            extent: CGRect(x: 0, y: 0, width: subjects.original.width, height: subjects.original.height)
                        )
                        return SubjectPickerInstance(id: instance.id, boundingBox: instance.boundingBox, overlayImage: PlatformImage(cgImageRepresentation: overlay))
                    }
                    await MainActor.run {
                        guard generation == self.backgroundGeneration else { return }
                        self.cachedSubjects = subjects
                        self.cachedSubjectsSource = original
                        self.cachedPickerInstances = pickerInstances
                        self.isProcessing = false
                        self.subjectSelectionRequest = SubjectSelectionRequest(
                            baseImage: original,
                            instances: pickerInstances,
                            initiallySelected: Set(subjects.instances.map(\.id))
                        )
                    }
                    return
                }

                let selection = priorSelection ?? Set(subjects.instances.map(\.id))
                let mask = try backgroundRemoval.combinedMask(selecting: selection, from: subjects)

                await MainActor.run {
                    guard generation == self.backgroundGeneration else { return }
                    self.cachedSubjects = subjects
                    self.cachedSubjectsSource = original
                    self.selectedSubjectIDs = selection
                    self.applyPipeline(mask: mask, original: original)
                }
            } catch {
                await MainActor.run {
                    guard generation == self.backgroundGeneration else { return }
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }

    /// Den billiga delen av pipelinen (filter, bildkorrigeringar,
    /// bakgrundskompositering, formbeskärning) givet en FÄRDIG mask - delad
    /// av `removeBackground()`s snabbväg (redan cachad mask) och dess
    /// långsamma väg (nyss beräknad/ihopslagen mask). Körs alltid frikopplad
    /// från huvudtråden (`Task.detached`) eftersom kompositering/beskärning
    /// går via CoreImage, precis som tidigare.
    private func applyPipeline(mask: BackgroundRemovalService.ForegroundMask, original: PlatformImage) {
        let style = backgroundStyle.serviceStyle
        let shape = outputShape
        let shapeTransform = outputShapeTransform
        let filter = photoFilter
        let adjustments = imageAdjustments

        backgroundGeneration += 1
        let generation = backgroundGeneration

        Task.detached(priority: .userInitiated) { [backgroundRemoval, shapeCrop, photoFilterService, imageAdjustment] in
            do {
                let filtered = try photoFilterService.apply(filter, to: original)
                let adjustedCG = try imageAdjustment.apply(adjustments, to: filtered).cgImageRepresentation
                let composited = try backgroundRemoval.composite(mask, background: style, foregroundImage: adjustedCG)
                let shaped = try shapeCrop.apply(shape, to: composited, transform: shapeTransform)
                await MainActor.run {
                    guard generation == self.backgroundGeneration else { return }
                    self.compositedImage = composited
                    self.processedImage = shaped
                    self.isProcessing = false
                    self.cachedMask = mask
                    self.cachedMaskSource = original
                    self.refreshShareURL()
                }
            } catch {
                await MainActor.run {
                    guard generation == self.backgroundGeneration else { return }
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }

    /// Anropas när användaren bekräftar sitt motivval i motivväljaren -
    /// fortsätter pipelinen (kompositering/formbeskärning) med de valda
    /// instansernas ihopslagna mask.
    public func confirmSubjectSelection(_ selected: Set<Int>) {
        if selected != selectedSubjectIDs {
            pushUndoSnapshot()
        }
        subjectSelectionRequest = nil
        selectedSubjectIDs = selected
        // Ogiltigförklara den redan beräknade masken - annars skulle
        // removeBackground()s snabbväg (cachedMask redan satt sedan en
        // TIDIGARE bekräftelse, t.ex. via "Motiv…"-knappen) återanvända
        // FÖRRA motivvalets mask istället för att räkna om för det NYA
        // valet (upptäckt när cachedMask-flödet spårades för undo/redo).
        cachedMask = nil
        cachedMaskSource = nil
        removeBackground()
    }

    /// Avbryter motivväljaren utan att ändra något - samma mönster som
    /// `cancelMaskEditing()`/`cancelCustomBackgroundPositioning()`.
    public func cancelSubjectSelection() {
        subjectSelectionRequest = nil
        isProcessing = false
    }

    /// Öppnar motivväljaren igen med nuvarande val förifyllt, t.ex. om
    /// användaren råkade välja fel motiv första gången. Kör INTE om
    /// Vision-analysen - återanvänder `cachedSubjects`/`cachedPickerInstances`.
    /// No-opar om bilden bara har ett motiv (väljaren är då aldrig relevant).
    public func reopenSubjectPicker() {
        guard let original = originalImage,
              cachedSubjectsSource === original,
              let subjects = cachedSubjects,
              subjects.instances.count > 1,
              let pickerInstances = cachedPickerInstances else { return }
        subjectSelectionRequest = SubjectSelectionRequest(
            baseImage: original,
            instances: pickerInstances,
            initiallySelected: selectedSubjectIDs ?? Set(subjects.instances.map(\.id))
        )
    }

    /// Sant om aktuell bild har flera separata motiv att välja mellan -
    /// styr om "Motiv…"-knappen visas i `DetailPanel`.
    public var hasMultipleSubjects: Bool {
        (cachedSubjects?.instances.count ?? 0) > 1
    }

    /// Bästa tillgängliga mask för snabba förhandsvisningar - t.ex.
    /// `BackgroundStylePickerView`s rutnät med riktiga bakgrunds-
    /// förhandsgranskningar, INNAN användaren faktiskt valt något.
    /// Återanvänder `cachedMask` om den redan finns (ingen extra kostnad).
    /// Annars körs Vision EN gång och ALLA hittade motiv slås ihop UTAN
    /// att fråga om motivval - det här är bara en förhandstitt, inte det
    /// slutgiltiga valet. Det RIKTIGA valet (`setBackgroundStyle`) går
    /// fortfarande genom hela, korrekta motivväljar-flödet (frågar om
    /// motiv vid behov) när användaren faktiskt trycker på ett alternativ.
    /// Cachar den råa Vision-detekteringen (`cachedSubjects`, bara en
    /// funktion av BILDEN, inte av motivvalet) om den behövde beräknas här,
    /// så det riktiga flödet sedan slipper köra Vision igen.
    public func previewMask() async -> BackgroundRemovalService.ForegroundMask? {
        guard let original = originalImage else { return nil }

        if cachedMaskSource === original, let mask = cachedMask {
            return mask
        }

        let subjects: BackgroundRemovalService.DetectedSubjects
        if cachedSubjectsSource === original, let cached = cachedSubjects {
            subjects = cached
        } else {
            guard let detected = try? await Task.detached(priority: .userInitiated) { [backgroundRemoval] in
                try backgroundRemoval.detectSubjects(in: original)
            }.value else { return nil }
            // Bilden kan i teorin ha bytts medan Vision körde - skriv bara
            // till cachen om den fortfarande gäller aktuell bild.
            if originalImage === original {
                cachedSubjects = detected
                cachedSubjectsSource = original
            }
            subjects = detected
        }

        let selection = selectedSubjectIDs ?? Set(subjects.instances.map(\.id))
        return try? await Task.detached(priority: .userInitiated) { [backgroundRemoval] in
            try backgroundRemoval.combinedMask(selecting: selection, from: subjects)
        }.value
    }

    /// Kastar bort allt bakgrunds-/form-/positioneringsval och går tillbaka
    /// till den obehandlade originalbilden - en "ångra allt"-knapp. Ökar
    /// `backgroundGeneration` så en ev. redan pågående `removeBackground()`
    /// inte skriver över återställningen när den sedan blir klar.
    public func restoreOriginal() {
        pushUndoSnapshot()
        backgroundGeneration += 1
        adjustmentGeneration += 1
        processedImage = nil
        compositedImage = nil
        adjustedPreviewImage = nil
        backgroundStyle = .transparent
        photoFilter = .none
        imageAdjustments = .identity
        outputShape = .square
        outputShapeTransform = .identity
        lastCommittedTransform = .identity
        isProcessing = false
        errorMessage = nil
        // Rör INTE `cachedMask`/`cachedSubjects`/`selectedSubjectIDs` -
        // precis som `cachedMask` redan behölls här innan (samma bild, så
        // nästa "Ta bort bakgrund" ska fortfarande slippa köra om Vision),
        // ska ett redan gjort motivval också överleva en "Återställ".
        subjectSelectionRequest = nil
        // `currentExportImage` faller nu tillbaka till originalbilden -
        // uppdatera delningsfilen så "Dela" inte pekar på det bortkastade
        // resultatet.
        refreshShareURL()
    }

    /// Byter bakgrundsval och tillämpar det direkt ("byta bakgrund med ett
    /// klick") - körs ALLTID om, inte bara när ett urklipp redan finns.
    /// Annars sparades valet bara tyst utan synlig effekt om man ännu inte
    /// hunnit trycka "Ta bort bakgrund" en första gång, vilket kändes som
    /// att vissa val "inte fungerade" (upptäckt 2026-09-25). `removeBackground()`
    /// no-opar redan ofarligt om ingen bild är inläst.
    public func setBackgroundStyle(_ style: BackgroundOption) {
        if style != backgroundStyle {
            pushUndoSnapshot()
        }
        backgroundStyle = style
        removeBackground()
    }

    /// Byter valt filter (färdig bildstil, t.ex. svartvitt/röntgen/sepia)
    /// och tillämpar det direkt - av samma anledning och på samma sätt som
    /// `setImageAdjustments` nedan.
    public func setPhotoFilter(_ filter: PhotoFilter) {
        photoFilter = filter
        refreshEditPreview()
        if processedImage != nil {
            removeBackground()
        }
    }

    /// Uppdaterar bildkorrigeringarna (ljusstyrka/kontrast/mättnad/
    /// temperatur/highlights/shadows/skärpa/brusreducering/vinjett).
    /// Räknar ALLTID om en ren, billig CoreImage-förhandsvisning direkt
    /// (`adjustedPreviewImage`, ingen Vision inblandad) så man ser effekten
    /// omedelbart även innan bakgrunden någonsin bearbetats. Komponerar
    /// dessutom om det FULLA resultatet, men bara om ett urklipp redan
    /// finns - av samma anledning som `commitOutputShapeTransform`: att
    /// bara justera skärpa/ljusstyrka/filter på originalet ska inte tyst
    /// trigga en riktig bakgrundsborttagning med standardbakgrunden.
    public func setImageAdjustments(_ adjustments: ImageAdjustments) {
        imageAdjustments = adjustments
        refreshEditPreview()
        if processedImage != nil {
            removeBackground()
        }
    }

    /// Räknar om `adjustedPreviewImage` - filter + bildkorrigeringar
    /// tillämpade på originalet, ingen Vision inblandad. Delad av
    /// `setPhotoFilter` och `setImageAdjustments`.
    private func refreshEditPreview() {
        guard let original = originalImage else { return }
        let filter = photoFilter
        let adjustments = imageAdjustments

        adjustmentGeneration += 1
        let generation = adjustmentGeneration

        Task.detached(priority: .userInitiated) { [photoFilterService, imageAdjustment] in
            guard let filtered = try? photoFilterService.apply(filter, to: original),
                  let preview = try? imageAdjustment.apply(adjustments, to: filtered) else { return }
            await MainActor.run {
                guard generation == self.adjustmentGeneration else { return }
                self.adjustedPreviewImage = preview
            }
        }
    }

    /// Byter slutbildens form (kvadrat/cirkel/hexagon/...). `SubjectFramingCanvas`
    /// klipper redan visuellt till den nya formen direkt via bindningen till
    /// `outputShape` (samma mekanism som `ManipulableImageView`s clipShape) -
    /// till skillnad från t.ex. bakgrundsstil har formvalet alltså redan en
    /// synlig effekt utan att någon riktig bearbetning körs. Kör därför bara
    /// om `removeBackground()` villkorat av `if processedImage != nil` -
    /// precis som `commitOutputShapeTransform` - annars skulle att bara
    /// VÄLJA en form (t.ex. efter att ha justerat ljusstyrka/filter men
    /// innan bakgrunden någonsin tagits bort) tyst trigga en riktig
    /// Vision-körning med standardbakgrunden (genomskinlig), vilket
    /// upplevdes som att "bakgrunden försvinner" bara av att välja form
    /// (upptäckt 2026-09-25) - samma bugg som `commitOutputShapeTransform`
    /// redan fixades för, fast för formmenyn istället för dra-gesten.
    /// Positioneringen (pan/zoom) i `outputShapeTransform` behålls oförändrad
    /// - den avser var i motivet formen läggs, inte formen själv.
    public func setOutputShape(_ shape: OutputShape) {
        if shape != outputShape {
            pushUndoSnapshot()
        }
        outputShape = shape
        if processedImage != nil {
            removeBackground()
        }
    }

    /// Anropas när användaren släpper en dra-/nyp-/rotationsgest i den
    /// inbäddade formramningen (`SubjectFramingCanvas`) - `outputShapeTransform`
    /// är redan uppdaterad via bindningen dit. Körs BARA om bearbetning
    /// redan skett minst en gång tidigare (till skillnad från
    /// `setBackgroundStyle`/`setOutputShape`, som alltid kör om) - annars
    /// skulle bara det att panorera/zooma/rotera för att komponera bilden,
    /// INNAN man bett om bakgrundsborttagning över huvud taget, tyst
    /// trigga en riktig Vision-körning med standardbakgrunden
    /// (genomskinlig), vilket upplevdes som att "bakgrunden försvinner när
    /// jag bara drar i bilden" (upptäckt 2026-09-25).
    public func commitOutputShapeTransform() {
        pushUndoSnapshot(overridingTransform: lastCommittedTransform)
        lastCommittedTransform = outputShapeTransform
        if processedImage != nil {
            removeBackground()
        }
    }

    /// Läser in en bildfil som egen bakgrund (via filväljaren i DetailPanel)
    /// och öppnar positioneraren så användaren kan panorera/zooma den innan
    /// den tillämpas.
    public func setCustomBackground(from url: URL) async {
        do {
            let image = try await Self.loadImage(from: url)
            backgroundPositioningRequest = BackgroundPositioningRequest(image: image, initialTransform: .identity)
        } catch {
            errorMessage = "Kunde inte läsa bakgrundsbilden: \(error.localizedDescription)"
        }
    }

    /// Öppnar positioneraren igen för den bakgrundsbild som redan är vald,
    /// med dess nuvarande pan/zoom som utgångspunkt.
    public func beginRepositioningCustomBackground() {
        guard case .custom(let image, let transform) = backgroundStyle else { return }
        backgroundPositioningRequest = BackgroundPositioningRequest(image: image, initialTransform: transform)
    }

    public func confirmCustomBackground(image: PlatformImage, transform: CanvasTransform) {
        backgroundPositioningRequest = nil
        setBackgroundStyle(.custom(image, transform: transform))
    }

    public func cancelCustomBackgroundPositioning() {
        backgroundPositioningRequest = nil
    }

    /// Öppnar penselredigeraren för den senast beräknade masken. Kräver att
    /// "Ta bort bakgrund" redan körts en gång för aktuell bild.
    public func beginMaskEditing() {
        guard let original = originalImage,
              let cached = cachedMask,
              cachedMaskSource === original else { return }
        maskEditingRequest = MaskEditingRequest(baseImage: original, editableMask: EditableMask(copying: cached.mask))
    }

    /// Tar den redigerade masken från penselverktyget, cachar den som den
    /// nya masken för bilden, och komponerar om med aktuell bakgrundsstil.
    public func applyEditedMask(_ editableMask: EditableMask) {
        guard let cached = cachedMask else { return }
        pushUndoSnapshot()
        cachedMask = BackgroundRemovalService.ForegroundMask(original: cached.original, mask: editableMask.pixelBuffer)
        cachedMaskSource = originalImage
        maskEditingRequest = nil
        removeBackground()
    }

    public func cancelMaskEditing() {
        maskEditingRequest = nil
    }

    /// Läser in en bild som släppts (drag-and-drop) eller valts via
    /// filväljaren för bearbetning, utan att den kommer från ett sökresultat.
    public func loadImportedImage(from url: URL) async {
        errorMessage = nil
        isLoadingDetail = true
        do {
            let image = try await Self.loadImage(from: url)
            loadImportedImage(image, name: url.lastPathComponent)
        } catch {
            errorMessage = "Kunde inte läsa den släppta bilden: \(error.localizedDescription)"
        }
        isLoadingDetail = false
    }

    /// Läser in en bild från urklipp - reservväg för webbsidor (t.ex.
    /// ChatGPTs bildvisning) där native drag-and-drop av bilden inte
    /// startar alls; se `PlatformImage.fromPasteboard()`.
    public func pasteFromClipboard() {
        errorMessage = nil
        guard let image = PlatformImage.fromPasteboard() else {
            errorMessage = "Hittade ingen bild i urklipp. Högerklicka bilden i webbläsaren och välj \"Kopiera bild\" först."
            return
        }
        loadImportedImage(image, name: "Inklistrad bild")
    }

    public func loadImportedImage(_ image: PlatformImage, name: String) {
        selectedItem = SearchResultItem(id: "imported-\(UUID().uuidString)", title: name)
        originalImage = image
        processedImage = nil
        compositedImage = nil
        adjustedPreviewImage = nil
        backgroundStyle = .transparent
        photoFilter = .none
        imageAdjustments = .identity
        outputShape = .square
        outputShapeTransform = .identity
        errorMessage = nil
        isLoadingDetail = false
        // Ny bild - `cachedMaskSource`/`cachedSubjectsSource`s `===`-jämförelse
        // mot den NYA `originalImage` ogiltigförklarar redan den gamla cachen
        // automatiskt, men nollställ ändå motivvalet och stäng en ev. kvarlämnad
        // motivväljare explicit, annars kan ett stale val från FÖRRA bilden
        // råka återanvändas om `cachedSubjectsSource` av misstag pekade på
        // samma instans (t.ex. samma `PlatformImage` återanvänd).
        cachedMask = nil
        cachedMaskSource = nil
        cachedSubjects = nil
        cachedSubjectsSource = nil
        cachedPickerInstances = nil
        selectedSubjectIDs = nil
        subjectSelectionRequest = nil
        // Ny bild - gammal historik gäller ett helt annat motiv, håll den
        // inte kvar.
        undoStack.removeAll()
        redoStack.removeAll()
        editSessionSnapshot = nil
        lastCommittedTransform = .identity
        updateUndoRedoAvailability()
        refreshShareURL()
    }

    private static func loadImage(from url: URL) async throws -> PlatformImage {
        let data: Data
        if url.isFileURL {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            data = try Data(contentsOf: url)
        } else {
            (data, _) = try await URLSession.shared.data(from: url)
        }
        guard let image = PlatformImage.normalizedOrientation(from: data) else {
            throw LoadImageError.invalidImageData
        }
        return image
    }

    private enum LoadImageError: LocalizedError {
        case invalidImageData
        var errorDescription: String? { "Filen var inte en giltig bild." }
    }

    /// Bilden "Spara"/"Dela" opererar på just nu - det färdiga
    /// bakgrunds-/formbearbetade resultatet om det finns, annars den rena
    /// filter-/justeringsförhandsvisningen (ingen Vision inblandad), annars
    /// originalet helt oförändrat. Samma fallback-ordning `save()` alltid
    /// använt - annars skulle bildkorrigeringar man gjort men ALDRIG kört
    /// bakgrundsborttagning för (processedImage fortfarande nil) sparas/
    /// delas bort tyst.
    public var currentExportImage: PlatformImage? {
        processedImage ?? adjustedPreviewImage ?? originalImage
    }

    private func exportFileName() -> String {
        let safeName = (selectedItem?.title ?? "bild")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ".jpg", with: "")
            .replacingOccurrences(of: ".jpeg", with: "")
            .replacingOccurrences(of: ".png", with: "")
        return safeName + "." + exportFormat.fileExtension
    }

    public func save() {
        guard let image = currentExportImage else { return }
        let fileName = exportFileName()

        Task {
            do {
                try await exporter.export(image: image, format: exportFormat, suggestedName: fileName)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Byter filformat för "Spara"/"Dela" - uppdaterar `shareURL` direkt så
    /// delningsknappen alltid pekar på en fil i RÄTT format, inte det
    /// tidigare valet.
    public func setExportFormat(_ format: ImageExportFormat) {
        exportFormat = format
        refreshShareURL()
    }

    /// Skriver om den temporära delningsfilen `shareURL` (använd av
    /// `ShareLink` i `DetailPanel` för att dela via Meddelanden/Mail/
    /// AirDrop m.fl.) - anropas varje gång bilden "Spara"/"Dela" skulle
    /// operera på ändras i grunden (nytt bearbetningsresultat, ny bild,
    /// eller bytt filformat). Körs synkront på huvudtråden - kodning av en
    /// redan färdig, färdigrenderad bild är snabbt nog (samma kostnad
    /// `save()` redan tar när man trycker Spara), och den behövs bara vid
    /// dessa distinkta, användarutlösta tillfällen - INTE t.ex. för varje
    /// litet reglageutslag i bildkorrigeringspanelen, vilket skulle skriva
    /// om filen orimligt ofta under en dra-gest.
    private func refreshShareURL() {
        guard let image = currentExportImage, let data = image.exportData(as: exportFormat) else {
            shareURL = nil
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(exportFileName())
        do {
            try data.write(to: url)
            shareURL = url
        } catch {
            shareURL = nil
        }
    }

    // MARK: - Undo/redo

    private func currentSnapshot() -> EditSnapshot {
        EditSnapshot(
            backgroundStyle: backgroundStyle,
            photoFilter: photoFilter,
            imageAdjustments: imageAdjustments,
            outputShape: outputShape,
            outputShapeTransform: outputShapeTransform,
            selectedSubjectIDs: selectedSubjectIDs,
            cachedMask: cachedMask
        )
    }

    /// Pushar NUVARANDE tillstånd (innan den ändring som är på väg att
    /// göras) som ETT undo-steg, och rensar `redoStack` - anropas i BÖRJAN
    /// av varje "sätt X direkt"-metod (bakgrund, form, motivval, pensel-
    /// redigering, återställ), INNAN själva ändringen görs.
    private func pushUndoSnapshot() {
        undoStack.append(currentSnapshot())
        redoStack.removeAll()
        updateUndoRedoAvailability()
    }

    /// Variant av `pushUndoSnapshot()` för `commitOutputShapeTransform()`,
    /// vars bindning redan skrivit det NYA värdet till `outputShapeTransform`
    /// innan metoden anropas - "innan"-läget måste därför byggas manuellt
    /// med `lastCommittedTransform` istället för att läsas ur nuvarande
    /// tillstånd. Se `lastCommittedTransform`s kommentar ovan.
    ///
    /// OBS: en sammansatt dra-/nyp-/vridgest i `ManipulableImageView`
    /// (se `CLAUDE.md`) kan anropa `onCommit`/den här vägen UPP TILL TRE
    /// gånger för EN enda fysisk tvåfingersgest (en `onEnded` per
    /// dra/nyp/vrid-delgest) - det kan alltså ge flera undo-steg för vad
    /// som känns som en enda gest. Medvetet accepterad avvägning: att
    /// koalescera dem hade krävt att röra den hårt förvärvade, sköra
    /// sammansatta gesten - se `CLAUDE.md`s varning om det. Inte en bugg,
    /// bara grövre granularitet än idealt för just den gesten.
    private func pushUndoSnapshot(overridingTransform transform: CanvasTransform) {
        let current = currentSnapshot()
        guard current.outputShapeTransform != transform else { return }
        let before = EditSnapshot(
            backgroundStyle: current.backgroundStyle,
            photoFilter: current.photoFilter,
            imageAdjustments: current.imageAdjustments,
            outputShape: current.outputShape,
            outputShapeTransform: transform,
            selectedSubjectIDs: current.selectedSubjectIDs,
            cachedMask: current.cachedMask
        )
        undoStack.append(before)
        redoStack.removeAll()
        updateUndoRedoAvailability()
    }

    private func updateUndoRedoAvailability() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    /// Öppnar en "session" (Justera-panelen eller Filter-väljaren) - sparar
    /// tillståndet INNAN sessionen började, men pushar det INTE till
    /// historiken än. Flera ändringar under sessionen ska räknas som ETT
    /// enda undo-steg. Anropad från `DetailPanel` när respektive sheet
    /// visas (även vid nedswepning, inte bara den uttryckliga
    /// "Klart"-knappen - se `.onChange` där).
    public func beginEditSession() {
        editSessionSnapshot = currentSnapshot()
    }

    /// Avslutar en pågående session och pushar dess "innan"-läge som ETT
    /// undo-steg - men bara om något faktiskt ändrades (annars skulle t.ex.
    /// att bara öppna och stänga Justera-panelen utan att röra något lägga
    /// till ett tomt, meningslöst undo-steg).
    public func endEditSession() {
        guard let snapshot = editSessionSnapshot else { return }
        editSessionSnapshot = nil
        guard snapshot != currentSnapshot() else { return }
        undoStack.append(snapshot)
        redoStack.removeAll()
        updateUndoRedoAvailability()
    }

    /// Återställer allt redigeringsval till en tidigare sparad ögonblicksbild
    /// - delad av `undo()`/`redo()`. Använder `applyPipeline` direkt med den
    /// sparade masken (INGEN ny Vision-körning behövs - masken är redan
    /// beräknad och sparad i ögonblicksbilden), precis som `removeBackground()`s
    /// egen snabbväg.
    private func apply(_ snapshot: EditSnapshot) {
        backgroundStyle = snapshot.backgroundStyle
        photoFilter = snapshot.photoFilter
        imageAdjustments = snapshot.imageAdjustments
        outputShape = snapshot.outputShape
        outputShapeTransform = snapshot.outputShapeTransform
        lastCommittedTransform = snapshot.outputShapeTransform
        selectedSubjectIDs = snapshot.selectedSubjectIDs
        cachedMask = snapshot.cachedMask
        errorMessage = nil

        guard let original = originalImage else { return }

        if let mask = snapshot.cachedMask {
            cachedMaskSource = original
            isProcessing = true
            applyPipeline(mask: mask, original: original)
        } else {
            // Tillbaka till ett läge FÖRE någon bakgrundsborttagning någonsin
            // kört (det allra första steget i historiken) - inget att
            // kompositera, bara den lätta filter-/justeringsförhandsvisningen.
            cachedMaskSource = nil
            processedImage = nil
            compositedImage = nil
            isProcessing = false
            refreshEditPreview()
            refreshShareURL()
        }
    }

    public func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot())
        apply(snapshot)
        updateUndoRedoAvailability()
    }

    public func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot())
        apply(snapshot)
        updateUndoRedoAvailability()
    }
}
