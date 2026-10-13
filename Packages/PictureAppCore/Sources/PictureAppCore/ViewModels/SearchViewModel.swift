import SwiftUI

@MainActor
public final class SearchViewModel: ObservableObject {
    @Published public var query: String = ""
    // "Egen bild" är default, inte "Webb/AI" - de flesta öppnar appen för
    // att redigera en bild de redan har, inte för att söka/generera en ny.
    @Published public var sourceKind: ImageSourceKind = .ownImage
    @Published public var searchEngine: ImageSource = .engine(.google)
    @Published public var errorMessage: String?
    /// Kort bekräftelse ("Bilden sparades") som visas en stund efter en lyckad
    /// sparning - annars sker sparningen tyst.
    @Published public var saveConfirmation: String?
    private var saveConfirmationToken = 0
    /// Sant när det finns en sparad, pågående redigering på disk att
    /// återuppta (visas som "Fortsätt där du slutade" i tomtillståndet) - se
    /// `SessionStore`.
    @Published public private(set) var hasSavedSession = false
    /// Billig, nedskalad förhandsvisning medan ett Justera-reglage dras
    /// (se `previewImageAdjustments`) - den FULLA pipelinen körs först när
    /// reglaget släpps.
    @Published public private(set) var livePreviewImage: PlatformImage?
    private var liveRunning = false
    private var livePending: ImageAdjustments?
    private var liveSmall: PlatformImage?
    private var liveSmallSource: PlatformImage?
    private var autosaveTask: Task<Void, Never>?

    @Published public var selectedItem: SearchResultItem?
    @Published public var originalImage: PlatformImage?
    // Motivet mot vald bakgrund, men INTE formbeskuret ännu (till skillnad
    // från `processedImage`) - källan för den inbäddade formramningen
    // (`SubjectFramingCanvas`), så man ser rätt bakgrund medan man
    // positionerar istället för det obehandlade originalet. Annars ser det
    // ut som att bakgrunden "kommer tillbaka" så fort man börjar justera
    // positionen (rapporterat 2026-09-25).
    @Published public var compositedImage: PlatformImage?
    // Motivet urklippt mot en GENOMSKINLIG bakgrund (aldrig `backgroundStyle`,
    // oavsett vad den är satt till), i originalbildens egen storlek - det
    // som faktiskt panoreras/zoomas/roteras i `SubjectFramingCanvas`, se
    // `applyPipeline`s dokumentation för varför. Hålls isär från
    // `compositedImage` (som har VALD bakgrund bakad in över HELA
    // originalrektangeln) eftersom den inte kan panoreras fritt utan att
    // bakgrunden följer med och lämnar tomrum där rektangeln inte längre
    // täcker kanvasen (se `buggs.md`) - `SubjectFramingCanvas` ritar därför
    // ett separat, fast bakgrundslager BAKOM den här bilden istället.
    @Published public var subjectCutoutImage: PlatformImage?
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
    // gated bakom att välja bort bakgrund/byta bakgrund). `ShapePreset`
    // bär BÅDE formens siluett (`.contour`, motsvarande gamla `OutputShape`)
    // OCH ett valfritt bildförhållande/exportpixelmål (praktiska genvägar
    // som "LinkedIn-profil") - se `ShapePreset`s egen dokumentation.
    @Published public var shapePreset: ShapePreset = .square
    /// Skugga/kontur på motivets urklipp - se `SubjectEffects`.
    @Published public var subjectEffects: SubjectEffects = .none
    @Published public var outputShapeTransform: CanvasTransform = .identity
    /// Texten som ligger ovanpå bilden (`nil` = ingen). Ändras LIVE via
    /// bindningar i `DetailPanel` (dra/skriva) utan att köra pipelinen -
    /// själva förhandsvisningen är ett SwiftUI-lager - och "committas" först
    /// när en gest/redigeringsrutan avslutas, se `commitOverlays()`.
    @Published public var textOverlay: TextOverlay?
    /// Logotypen/bilden som ligger ovanpå (under texten) - samma live-/commit-
    /// modell som `textOverlay`, se `commitOverlays()`.
    @Published public var logoOverlay: LogoOverlay?
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
        let shapePreset: ShapePreset
        let subjectEffects: SubjectEffects
        var outputShapeTransform: CanvasTransform
        var textOverlay: TextOverlay?
        var logoOverlay: LogoOverlay?
        let selectedSubjectIDs: Set<Int>?
        let cachedMask: BackgroundRemovalService.ForegroundMask?
    }

    private let exporter: ImageExporter
    private let backgroundRemoval = BackgroundRemovalService()
    private let shapeCrop = ShapeCropService()
    private let imageAdjustment = ImageAdjustmentService()
    private let photoFilterService = PhotoFilterService()
    private let textOverlayService = TextOverlayService()
    private let logoOverlayService = LogoOverlayService()
    private let subjectEffectService = SubjectEffectService()
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
    // Motsvarande för `textOverlay` - se `commitOverlays()`.
    private var lastCommittedTextOverlay: TextOverlay?
    private var lastCommittedLogoOverlay: LogoOverlay?
    // Ökas för varje `refreshShareURL()` så ett sent svar från en äldre
    // (nu bakgrundskörd) delningsfil inte skriver över en nyare.
    private var shareGeneration = 0
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
        return searchEngine.url(for: trimmed)
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
    ///
    /// Ordningen är MEDVETET `colorLook` → urklipp (genomskinlig bakgrund) →
    /// positionera urklippet i kanvasen → rendera bakgrunden I KANVASENS
    /// storlek → lägg urklippet ÖVER bakgrunden → formsiluett → `layoutWrap`,
    /// INTE `apply` (look+layout ihop) rakt av som i `refreshEditPreview()`s
    /// mask-fria förhandsvisning - Polaroid/Fotoautomats ram/remsa gör
    /// bilden STÖRRE än originalet, och Visions `mask` är beräknad för
    /// ORIGINALETS dimensioner. Om ramen/remsan låg FÖRE kompositeringen
    /// skulle masken hamna fel mot den nya, större bilden (fel del av
    /// resultatet skulle bli "motiv" kontra "bakgrund"), och formbeskärningen
    /// skulle klippa bort själva ramen/remsan istället för att forma MOTIVET.
    /// Genom att lägga `layoutWrap` sist, EFTER att motivet redan är
    /// bakgrundsbytt och formbeskuret, blir varje Fotoautomat-ruta/Polaroid-
    /// foto exakt det användaren redan positionerat. För alla andra (rena
    /// färg-)filter är `layoutWrap` en no-op, så deras beteende är oförändrat.
    ///
    /// Bakgrunden komponeras MEDVETET separat, i SLUTKANVASENS storlek -
    /// inte genom att bakgrundslägga mot hela originalbilden och sedan
    /// formbeskära/positionera DEN (tidigare ordning) - annars fyller en
    /// vald bakgrundsfärg bara den positionerade bildens EGNA gränser
    /// istället för hela kanvasen, och lämnar checkerboard i resten så fort
    /// motivet panorerats så en kant av kanvasen exponeras (se `buggs.md`).
    private func applyPipeline(mask: BackgroundRemovalService.ForegroundMask, original: PlatformImage) {
        let style = backgroundStyle.serviceStyle
        let preset = shapePreset
        let shapeTransform = outputShapeTransform
        let filter = photoFilter
        let adjustments = imageAdjustments
        let effects = subjectEffects
        let overlay = textOverlay
        let logo = logoOverlay

        backgroundGeneration += 1
        let generation = backgroundGeneration

        Task.detached(priority: .userInitiated) { [backgroundRemoval, shapeCrop, photoFilterService, imageAdjustment, textOverlayService, logoOverlayService, subjectEffectService] in
            do {
                let looked = try photoFilterService.colorLook(filter, to: original)
                let adjustedCG = try imageAdjustment.apply(adjustments, to: looked).cgImageRepresentation
                let referenceImage = adjustedCG ?? mask.original

                // Motivet, urklippt mot en GENOMSKINLIG bakgrund - det som
                // panoreras i `SubjectFramingCanvas` (se `subjectCutoutImage`s
                // dokumentation) OCH det som positioneras i kanvasen nedan.
                let plainCutout = try backgroundRemoval.composite(mask, background: .transparent, foregroundImage: adjustedCG)
                // Skugga/kontur bakas in i urklippet så att förhandsvisning
                // och export blir identiska och följer motivet.
                let cutout = try subjectEffectService.apply(effects, to: plainCutout)

                // Positionera/beskär URKLIPPET (inte hela bilden) i kanvasen -
                // `allowsExposedEdges: true` (redan satt i `ShapeCropService`)
                // släpper igenom genomskinlighet både från själva urklippet
                // OCH från att panorera det utanför kanvasen.
                let positionedSubject = try shapeCrop.positioned(preset, image: cutout, transform: shapeTransform)

                // Bakgrunden renderas separat, i SLUTKANVASENS storlek
                // (`positionedSubject.size` - alltid samma som `preset`s
                // `canvasSize`) - inte originalbildens - så den fyller HELA
                // kanvasen oavsett var motivet råkar vara positionerat.
                let canvasBackground = try backgroundRemoval.backgroundFill(style, referenceImage: referenceImage, canvasSize: positionedSubject.size)
                let canvasComposite = try backgroundRemoval.compositeOverCanvas(subject: positionedSubject, backgroundFill: canvasBackground)

                // Fortfarande VALD bakgrund bakad in över HELA originalets
                // rektangel (inte kanvasen) - se `compositedImage`s
                // dokumentation för varför `ShapePickerView` fortfarande
                // behöver den formen.
                let composited = try backgroundRemoval.composite(mask, background: style, foregroundImage: adjustedCG)

                // Logotypen och texten (i den ordningen - texten överst) ritas på
                // den färdiga kompositen FÖRE siluetten, så de klipps av formen
                // precis som motiv och bakgrund.
                let withText = Self.applyOverlays(logo: logo, text: overlay, to: canvasComposite, logoService: logoOverlayService, textService: textOverlayService)
                let shaped = try shapeCrop.applyingSilhouette(preset.contour, freeform: preset.freeform, to: withText)
                // Praktiska genvägar (t.ex. "Instagram-inlägg") tvingar EXAKT
                // exportpixelmått - `nil` (de generiska formerna) lämnar
                // storleken oförändrad, precis som innan `ShapePreset` fanns.
                let sized = preset.pixelSize.map { shaped.resized(to: $0) } ?? shaped
                let final = try photoFilterService.layoutWrap(filter, wrapping: sized)
                await MainActor.run {
                    guard generation == self.backgroundGeneration else { return }
                    self.subjectCutoutImage = cutout
                    self.compositedImage = composited
                    self.processedImage = final
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
        subjectCutoutImage = nil
        adjustedPreviewImage = nil
        backgroundStyle = .transparent
        photoFilter = .none
        imageAdjustments = .identity
        shapePreset = .square
        subjectEffects = .none
        outputShapeTransform = .identity
        lastCommittedTransform = .identity
        textOverlay = nil
        lastCommittedTextOverlay = nil
        logoOverlay = nil
        lastCommittedLogoOverlay = nil
        isProcessing = false
        errorMessage = nil
        // Kasta motivvalet och den (ev. pensel-redigerade) färdiga masken -
        // annars visade Bakgrund-/Form-väljarnas förhandsvisningar (som
        // bygger på `previewMask()`) fortfarande det gamla valet/penseln
        // efter en "Återställ". Behåll bara `cachedSubjects` (Visions råa
        // detektering av originalbilden, opåverkad av användarens val) så
        // nästa "Ta bort bakgrund" slipper köra om Vision.
        cachedMask = nil
        cachedMaskSource = nil
        selectedSubjectIDs = nil
        subjectSelectionRequest = nil
        maskEditingRequest = nil
        backgroundPositioningRequest = nil
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
        // Siluetten är bara meningsfull MOT ett urklipp (annars blir hela
        // rektangeln svart) - kör därför alltid bakgrundsborttagningen.
        if processedImage != nil || filter == .silhouette {
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
        livePending = nil
        imageAdjustments = adjustments
        refreshEditPreview()
        if processedImage != nil {
            removeBackground()
        }
    }

    /// Live-förhandsvisning MEDAN ett reglage dras: filter + justeringar på
    /// en NEDSKALAD kopia (max 900 px), en körning i taget (senaste värdet
    /// vinner). Rör varken `shareURL`, Vision eller den fulla pipelinen -
    /// att köra den per reglageutslag på en full-upplöst iPhone-bild tog
    /// slut på minnet och appen stängdes (rapporterat 2026-10-13). Själva
    /// justeringen läggs i `setImageAdjustments` när reglaget släpps.
    public func previewImageAdjustments(_ adjustments: ImageAdjustments) {
        imageAdjustments = adjustments
        livePending = adjustments
        runLivePreview()
    }

    private func runLivePreview() {
        guard !liveRunning, let adjustments = livePending, let original = originalImage else { return }
        livePending = nil
        liveRunning = true
        let filter = photoFilter
        let cachedSmall = (liveSmallSource === original) ? liveSmall : nil

        Task.detached(priority: .userInitiated) { [photoFilterService, imageAdjustment] in
            let small = cachedSmall ?? original.resized(maxDimension: 900)
            let preview: PlatformImage? = {
                guard let filtered = try? photoFilterService.apply(filter, to: small) else { return nil }
                return try? imageAdjustment.apply(adjustments, to: filtered)
            }()
            await MainActor.run {
                self.liveSmall = small
                self.liveSmallSource = original
                self.liveRunning = false
                if let preview {
                    self.livePreviewImage = preview
                }
                self.runLivePreview()
            }
        }
    }

    /// Räknar om `adjustedPreviewImage` - filter + bildkorrigeringar
    /// tillämpade på originalet, ingen Vision inblandad. Delad av
    /// `setPhotoFilter` och `setImageAdjustments`.
    ///
    /// Uppdaterar ALLTID `shareURL` här också (inte bara `adjustedPreviewImage`)
    /// - `currentExportImage`/"Dela" faller tillbaka på just `adjustedPreviewImage`
    /// så länge `processedImage` är `nil` (ingen riktig bakgrundsborttagning
    /// körd än), så om `shareURL` inte hänger med HÄR pekar "Dela" (t.ex. som
    /// SMS) tyst på filen från INNAN редigeringen - upptäckt 2026-09-26,
    /// samma klass av bugg som SayFrame/Persona-repots exportbugg: en
    /// manuellt underhållen "cache" (`shareURL`) som måste följa med vid
    /// VARJE ställe den underliggande bilden ändras, inte bara några av dem.
    /// `restoreSnapshot`s undo/redo-väg råkade redan göra rätt (anropade
    /// båda tillsammans) - genom att lägga anropet HÄR istället kan inget
    /// framtida anrop till `refreshEditPreview()` missa det igen.
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
                self.livePreviewImage = nil
                self.refreshShareURL()
            }
        }
    }

    /// Byter slutbildens form/preset (kvadrat/cirkel/LinkedIn-profil/...).
    /// `SubjectFramingCanvas` klipper redan visuellt till den nya formen
    /// direkt via bindningen till `shapePreset` (samma mekanism som
    /// `ManipulableImageView`s clipShape) - till skillnad från t.ex.
    /// bakgrundsstil har formvalet alltså redan en synlig effekt utan att
    /// någon riktig bearbetning körs. Kör därför bara om `removeBackground()`
    /// villkorat av `if processedImage != nil` - precis som
    /// `commitOutputShapeTransform` - annars skulle att bara VÄLJA en form
    /// (t.ex. efter att ha justerat ljusstyrka/filter men innan bakgrunden
    /// någonsin tagits bort) tyst trigga en riktig Vision-körning med
    /// standardbakgrunden (genomskinlig), vilket upplevdes som att
    /// "bakgrunden försvinner" bara av att välja form (upptäckt 2026-09-25)
    /// - samma bugg som `commitOutputShapeTransform` redan fixades för,
    /// fast för formmenyn istället för dra-gesten. Positioneringen
    /// (pan/zoom) i `outputShapeTransform` behålls oförändrad - den avser
    /// var i motivet formen läggs, inte formen själv.
    public func setShapePreset(_ preset: ShapePreset) {
        if preset != shapePreset {
            pushUndoSnapshot()
        }
        shapePreset = preset
        if processedImage != nil {
            removeBackground()
        }
    }

    /// Sätter skugga/kontur på motivet och kör om pipelinen (ett undo-steg).
    public func setSubjectEffects(_ effects: SubjectEffects) {
        guard effects != subjectEffects else { return }
        pushUndoSnapshot()
        subjectEffects = effects
        removeBackground()
    }

    /// Anropas när användaren släpper en dra-/nyp-/rotationsgest i den
    /// inbäddade formramningen (`SubjectFramingCanvas`) - `outputShapeTransform`
    /// är redan uppdaterad via bindningen dit. Körs BARA om bearbetning
    /// redan skett minst en gång tidigare (till skillnad från
    /// `setBackgroundStyle`/`setShapePreset`, som alltid kör om) - annars
    /// skulle bara det att panorera/zooma/rotera för att komponera bilden,
    /// INNAN man bett om bakgrundsborttagning över huvud taget, tyst
    /// trigga en riktig Vision-körning med standardbakgrunden
    /// (genomskinlig), vilket upplevdes som att "bakgrunden försvinner när
    /// jag bara drar i bilden" (upptäckt 2026-09-25).
    public func commitOutputShapeTransform() {
        // En enda nyp-/dragning avfyrar `onCommit` upp till tre gånger (se
        // `pushUndoSnapshot(overridingTransform:)`), och de delgester som
        // inte ändrade något gav ändå en hel omkörning av pipelinen - gjorde
        // varje släpp segt. Ingen ändring = inget att göra.
        guard outputShapeTransform != lastCommittedTransform else { return }
        pushUndoSnapshot(overridingTransform: lastCommittedTransform)
        lastCommittedTransform = outputShapeTransform
        if processedImage != nil {
            removeBackground()
        } else {
            // Ingen bakgrundsborttagning körd - exportbilden byggs då av
            // `framedWithOverlays` (se `currentExportImage`), så delningsfilen
            // måste skrivas om för att följa position/spegling.
            refreshShareURL()
        }
    }

    /// Skapar en standardtext om ingen finns än (utan att pusha något
    /// undo-steg - det görs först av `commitOverlays()` när
    /// redigeringen avslutas, så att "lägg till + skriv" blir ETT steg).
    public func ensureTextOverlay() {
        if textOverlay == nil {
            textOverlay = TextOverlay(text: L("Din text"))
        }
    }

    /// Anropas när en dra-/nyp-/vridgest på texten eller logotypen släpps,
    /// eller när textredigeraren stängs - bakar in dem i exportbilden och
    /// pushar ETT undo-steg med `lastCommitted…` som "innan"-läge (samma
    /// mönster som `commitOutputShapeTransform()`; bindningarna har redan
    /// skrivit de nya värdena). En tom text räknas som "ingen text". Flera
    /// anrop i rad för samma gest är ofarliga - de följande ser ingen skillnad.
    public func commitOverlays() {
        if let overlay = textOverlay, !overlay.hasContent {
            textOverlay = nil
        }
        guard textOverlay != lastCommittedTextOverlay || logoOverlay != lastCommittedLogoOverlay else { return }
        var before = currentSnapshot()
        before.textOverlay = lastCommittedTextOverlay
        before.logoOverlay = lastCommittedLogoOverlay
        undoStack.append(before)
        redoStack.removeAll()
        updateUndoRedoAvailability()
        lastCommittedTextOverlay = textOverlay
        lastCommittedLogoOverlay = logoOverlay
        if processedImage != nil {
            removeBackground()
        } else {
            refreshShareURL()
        }
    }

    /// Läser in en bildfil som logotyp (via filväljaren i `DetailPanel`).
    /// Finns redan en logotyp byts bara bilden ut - placering, storlek och
    /// vridning behålls. PNG med genomskinlighet bevaras.
    public func setLogo(from url: URL) async {
        do {
            let image = try await Self.loadImage(from: url)
            if var existing = logoOverlay {
                existing.image = image
                logoOverlay = existing
            } else {
                logoOverlay = LogoOverlay(image: image)
            }
            commitOverlays()
        } catch {
            // Prefix lokaliserat för sig, felet konkatenerat EFTER - se
            // `setCustomBackground(from:)`.
            let prefix = String(localized: "Kunde inte läsa logotypen:", bundle: .module, locale: AppLanguage.current.locale)
            errorMessage = "\(prefix) \(error.localizedDescription)"
        }
    }

    /// Tar bort logotypen (✕ på markeringsramen).
    public func removeLogo() {
        logoOverlay = nil
        commitOverlays()
    }

    /// Zoomar motivet i formramningen ett steg (`factor` > 1 = in, < 1 = ut)
    /// - för +/−-knapparna under ramningsytan, så allt går att göra med bara
    /// en mus (nyp på styrplattan är inte ett krav). Samma väg som en gest:
    /// sätt transformen och committa (ett undo-steg, omkörning av pipelinen).
    public func zoomSubject(by factor: CGFloat) {
        var transform = outputShapeTransform
        transform.scale = min(max(transform.scale * factor, CanvasTransform.minScale), 8)
        outputShapeTransform = transform
        commitOutputShapeTransform()
    }

    /// Steget (i grader) för ↺/↻-knapparna under ramningsytan.
    public static let rotationStepDegrees: Double = 15

    /// Vrider motivet i formramningen `degrees` grader (positivt = medsols) -
    /// musalternativet till tvåfingers-vridning, se `zoomSubject(by:)`.
    public func rotateSubject(byDegrees degrees: Double) {
        var transform = outputShapeTransform
        transform.rotation += .degrees(degrees)
        outputShapeTransform = transform
        commitOutputShapeTransform()
    }

    /// Speglar motivet i formramningen horisontellt (växlar) - samma väg som
    /// en gest: sätt transformen och committa (ett undo-steg).
    public func mirrorSubject() {
        var transform = outputShapeTransform
        transform.isMirrored.toggle()
        outputShapeTransform = transform
        commitOutputShapeTransform()
    }

    /// Läser in en bildfil som egen bakgrund (via filväljaren i DetailPanel)
    /// och öppnar positioneraren så användaren kan panorera/zooma den innan
    /// den tillämpas.
    public func setCustomBackground(from url: URL) async {
        do {
            let image = try await Self.loadImage(from: url)
            backgroundPositioningRequest = BackgroundPositioningRequest(image: image, initialTransform: .identity)
        } catch {
            // Prefixet lokaliseras för sig, INTE hela strängen med
            // `\(error.localizedDescription)` interpolerad direkt i
            // `String(localized:)`-nyckeln - att handskriva rätt
            // "%@"-platshållarform i String Catalog-JSON:en för en
            // interpolerad nyckel är onödigt bräckligt (fel form ger en
            // TYST fallback till svenska istället för ett fel).
            let prefix = String(localized: "Kunde inte läsa bakgrundsbilden:", bundle: .module, locale: AppLanguage.current.locale)
            errorMessage = "\(prefix) \(error.localizedDescription)"
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
            let prefix = String(localized: "Kunde inte läsa den släppta bilden:", bundle: .module, locale: AppLanguage.current.locale)
            errorMessage = "\(prefix) \(error.localizedDescription)"
        }
        isLoadingDetail = false
    }

    /// Läser in en bild från urklipp - reservväg för webbsidor (t.ex.
    /// ChatGPTs bildvisning) där native drag-and-drop av bilden inte
    /// startar alls; se `PlatformImage.fromPasteboard()`.
    public func pasteFromClipboard() {
        errorMessage = nil
        guard let image = PlatformImage.fromPasteboard() else {
            errorMessage = String(localized: "Hittade ingen bild i urklipp. Högerklicka bilden i webbläsaren och välj \"Kopiera bild\" först.", bundle: .module, locale: AppLanguage.current.locale)
            return
        }
        loadImportedImage(image, name: String(localized: "Inklistrad bild", bundle: .module, locale: AppLanguage.current.locale))
    }

    public func loadImportedImage(_ image: PlatformImage, name: String) {
        selectedItem = SearchResultItem(id: "imported-\(UUID().uuidString)", title: name)
        originalImage = image
        processedImage = nil
        compositedImage = nil
        subjectCutoutImage = nil
        adjustedPreviewImage = nil
        backgroundStyle = .transparent
        photoFilter = .none
        imageAdjustments = .identity
        shapePreset = .square
        subjectEffects = .none
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
        textOverlay = nil
        lastCommittedTextOverlay = nil
        logoOverlay = nil
        lastCommittedLogoOverlay = nil
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
        var errorDescription: String? {
            String(localized: "Filen var inte en giltig bild.", bundle: .module, locale: AppLanguage.current.locale)
        }
    }

    /// Bilden "Spara"/"Dela" opererar på just nu - det färdiga
    /// bakgrunds-/formbearbetade resultatet om det finns, annars den rena
    /// filter-/justeringsförhandsvisningen (ingen Vision inblandad), annars
    /// originalet helt oförändrat. Samma fallback-ordning `save()` alltid
    /// använt - annars skulle bildkorrigeringar man gjort men ALDRIG kört
    /// bakgrundsborttagning för (processedImage fortfarande nil) sparas/
    /// delas bort tyst.
    public var currentExportImage: PlatformImage? {
        if let processedImage { return processedImage }
        let base = adjustedPreviewImage ?? originalImage
        let text = textOverlay?.hasContent == true ? textOverlay : nil
        guard let base, text != nil || logoOverlay != nil || outputShapeTransform != .identity else { return base }
        return Self.framedWithOverlays(logo: logoOverlay, text: text, on: base, preset: shapePreset, transform: outputShapeTransform, shapeCrop: shapeCrop, logoService: logoOverlayService, textService: textOverlayService)
    }

    /// Ritar logotyp och text på `image` - text överst om inte
    /// `logo.isInFront` är satt (se `LogoOverlay.isInFront`).
    nonisolated private static func applyOverlays(
        logo: LogoOverlay?,
        text: TextOverlay?,
        to image: PlatformImage,
        logoService: LogoOverlayService,
        textService: TextOverlayService
    ) -> PlatformImage {
        var result = image
        if logo?.isInFront == true {
            // Logotypen över texten.
            if let text { result = textService.apply(text, to: result) }
            if let logo { result = logoService.apply(logo, to: result) }
        } else {
            if let logo { result = logoService.apply(logo, to: result) }
            if let text { result = textService.apply(text, to: result) }
        }
        return result
    }

    /// Exportbild när en text/logotyp finns men bakgrundsborttagning aldrig
    /// körts (`processedImage == nil`): de är placerade relativt FORMENS
    /// kanvas (det man ser i `SubjectFramingCanvas`), så bilden måste
    /// beskäras till den kanvasen först - annars skulle de hamna på fel
    /// ställe i den obeskurna originalbilden. Samma ordning som
    /// `applyPipeline`: position → logotyp/text → siluett → exportmått.
    nonisolated private static func framedWithOverlays(
        logo: LogoOverlay?,
        text: TextOverlay?,
        on base: PlatformImage,
        preset: ShapePreset,
        transform: CanvasTransform,
        shapeCrop: ShapeCropService,
        logoService: LogoOverlayService,
        textService: TextOverlayService
    ) -> PlatformImage {
        guard let positioned = try? shapeCrop.positioned(preset, image: base, transform: transform) else { return base }
        let withOverlays = applyOverlays(logo: logo, text: text, to: positioned, logoService: logoService, textService: textService)
        guard let shaped = try? shapeCrop.applyingSilhouette(preset.contour, freeform: preset.freeform, to: withOverlays) else { return withOverlays }
        return preset.pixelSize.map { shaped.resized(to: $0) } ?? shaped
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
                if try await exporter.export(image: image, format: exportFormat, suggestedName: fileName) {
                    showSaveConfirmation()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func showSaveConfirmation() {
        #if os(iOS)
        saveConfirmation = L("Sparad i Foton.")
        #else
        saveConfirmation = L("Bilden sparades.")
        #endif
        saveConfirmationToken += 1
        let token = saveConfirmationToken
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if token == saveConfirmationToken { saveConfirmation = nil }
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
        scheduleAutosave()
        shareGeneration += 1
        let generation = shareGeneration
        let fileName = exportFileName()
        let format = exportFormat
        let processed = processedImage
        let base = adjustedPreviewImage ?? originalImage
        let overlay = textOverlay?.hasContent == true ? textOverlay : nil
        let logo = logoOverlay
        let preset = shapePreset
        let transform = outputShapeTransform

        // Kodning + filskrivning (och, med en text utan körd
        // bakgrundsborttagning, själva beskärningen/textritningen) av en
        // full upplösnings-bild är för tungt för huvudtråden - gjorde
        // dra-/nyp-/vridgester på bilden och texten trögga eftersom varje
        // släpp ledde hit. `shareGeneration` kastar ett för gammalt svar.
        Task.detached(priority: .utility) { [shapeCrop, textOverlayService, logoOverlayService] in
            let image: PlatformImage?
            if let processed {
                image = processed
            } else if let base, overlay != nil || logo != nil || transform != .identity {
                image = Self.framedWithOverlays(logo: logo, text: overlay, on: base, preset: preset, transform: transform, shapeCrop: shapeCrop, logoService: logoOverlayService, textService: textOverlayService)
            } else {
                image = base
            }
            var url: URL?
            if let image, let data = image.exportData(as: format) {
                let target = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                if (try? data.write(to: target)) != nil {
                    url = target
                }
            }
            await MainActor.run {
                guard generation == self.shareGeneration else { return }
                self.shareURL = url
            }
        }
    }

    // MARK: - Spara/återuppta pågående redigering

    /// Kollar om en sparad session finns - anropas när appen startar.
    public func refreshSavedSessionAvailability() async {
        hasSavedSession = await SessionStore.shared.hasSession()
    }

    /// Kastar den sparade sessionen (användaren vill börja om).
    public func discardSavedSession() async {
        autosaveTask?.cancel()
        await SessionStore.shared.clear()
        hasSavedSession = false
    }

    /// Läser in den sparade sessionen och återställer ALLA redigeringsval -
    /// bild, bakgrund, filter, justeringar, form, position, text, logotyp,
    /// motivval och den färdiga masken (inkl. penselredigeringar). Ångra-
    /// historiken sparas inte; den börjar om från det återupptagna läget.
    public func resumeSavedSession() async {
        isLoadingDetail = true
        guard let loaded = await SessionStore.shared.load() else {
            isLoadingDetail = false
            hasSavedSession = false
            errorMessage = L("Kunde inte öppna den sparade redigeringen.")
            return
        }
        let saved = loaded.session

        loadImportedImage(loaded.original, name: saved.title)

        let background: BackgroundOption
        switch saved.background.kind {
        case "color": background = .color(Color(srgbComponents: saved.background.color ?? []))
        case "blurred": background = .blurredOriginal
        case "gradient":
            if let preset = GradientPreset.all.first(where: { $0.id == saved.background.gradientID }) {
                background = .gradient(preset)
            } else {
                background = .transparent
            }
        case "custom":
            if let image = loaded.backgroundImage {
                background = .custom(image, transform: saved.background.transform?.canvasTransform ?? .identity)
            } else {
                background = .transparent
            }
        default: background = .transparent
        }

        let a = saved.adjustments
        let adjustments = a.count == 9
            ? ImageAdjustments(
                brightness: a[0], contrast: a[1], saturation: a[2], temperature: a[3], highlights: a[4],
                shadows: a[5], sharpness: a[6], noiseReduction: a[7], vignette: a[8]
            )
            : .identity

        let preset: ShapePreset
        if saved.shapeID == OutputShape.freeform.rawValue {
            if let points = saved.freeform {
                preset = .freeform(FreeformPath(points: points.compactMap { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil }))
            } else {
                preset = .freeformPlaceholder
            }
        } else {
            preset = ShapePreset.all.first { $0.id == saved.shapeID } ?? .square
        }

        var text: TextOverlay?
        if let t = saved.text {
            text = TextOverlay(
                text: t.text,
                fontStyle: TextFontStyle(rawValue: t.fontStyle) ?? .heavy,
                color: Color(srgbComponents: t.color),
                size: CGFloat(t.size),
                offset: CGSize(width: t.offsetX, height: t.offsetY),
                rotation: .degrees(t.rotationDegrees),
                hasShadow: t.hasShadow
            )
        }

        var logo: LogoOverlay?
        if let l = saved.logo, let image = loaded.logoImage {
            var overlay = LogoOverlay(
                image: image,
                size: CGFloat(l.size),
                offset: CGSize(width: l.offsetX, height: l.offsetY),
                rotation: .degrees(l.rotationDegrees),
                isFlipped: l.isFlipped
            )
            overlay.isInFront = l.isInFront
            logo = overlay
        }

        var mask: BackgroundRemovalService.ForegroundMask?
        if let buffer = loaded.mask, let cg = loaded.original.cgImageRepresentation {
            mask = BackgroundRemovalService.ForegroundMask(original: cg, mask: buffer)
        }

        let effects: SubjectEffects
        if let e = saved.effects, e.count == 2 {
            effects = SubjectEffects(shadow: e[0], outlineWidth: e[1], outlineColor: Color(srgbComponents: saved.outlineColor ?? []))
        } else {
            effects = .none
        }

        exportFormat = ImageExportFormat(rawValue: saved.exportFormat) ?? .png
        let snapshot = EditSnapshot(
            backgroundStyle: background,
            photoFilter: PhotoFilter(rawValue: saved.photoFilter) ?? .none,
            imageAdjustments: adjustments,
            shapePreset: preset,
            subjectEffects: effects,
            outputShapeTransform: saved.transform.canvasTransform,
            textOverlay: text,
            logoOverlay: logo,
            selectedSubjectIDs: saved.selectedSubjectIDs.map(Set.init),
            cachedMask: mask
        )
        apply(snapshot)
        isLoadingDetail = false
    }

    /// Debouncad autosparning - skrivs någon sekund efter SENASTE ändringen
    /// (anropad från `updateUndoRedoAvailability()`/`refreshShareURL()`, som
    /// tillsammans täcker allt som ändrar redigeringen). Gör inget förrän en
    /// bild är inläst, så en äldre sparad session inte skrivs över av ett
    /// tomt läge vid appstart.
    private func scheduleAutosave() {
        guard originalImage != nil else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self, let input = self.makeSessionInput() else { return }
            await SessionStore.shared.write(input)
            self.hasSavedSession = true
        }
    }

    private func makeSessionInput() -> SessionStore.Input? {
        guard let original = originalImage else { return nil }

        var background = SessionStore.SavedBackground(kind: "transparent", color: nil, gradientID: nil, transform: nil)
        var backgroundImage: PlatformImage?
        switch backgroundStyle {
        case .transparent: break
        case .color(let color): background = .init(kind: "color", color: color.srgbComponents, gradientID: nil, transform: nil)
        case .blurredOriginal: background = .init(kind: "blurred", color: nil, gradientID: nil, transform: nil)
        case .gradient(let preset): background = .init(kind: "gradient", color: nil, gradientID: preset.id, transform: nil)
        case .custom(let image, let transform):
            background = .init(kind: "custom", color: nil, gradientID: nil, transform: .init(transform))
            backgroundImage = image
        }

        var text: SessionStore.SavedText?
        if let t = textOverlay, t.hasContent {
            text = .init(
                text: t.text, fontStyle: t.fontStyle.rawValue, color: t.color.srgbComponents, size: Double(t.size),
                offsetX: Double(t.offset.width), offsetY: Double(t.offset.height),
                rotationDegrees: t.rotation.degrees, hasShadow: t.hasShadow
            )
        }

        var logo: SessionStore.SavedLogo?
        if let l = logoOverlay {
            logo = .init(
                size: Double(l.size), offsetX: Double(l.offset.width), offsetY: Double(l.offset.height),
                rotationDegrees: l.rotation.degrees, isFlipped: l.isFlipped, isInFront: l.isInFront
            )
        }

        let a = imageAdjustments
        let session = SessionStore.SavedSession(
            title: selectedItem?.title ?? "bild",
            exportFormat: exportFormat.rawValue,
            background: background,
            photoFilter: photoFilter.rawValue,
            adjustments: [a.brightness, a.contrast, a.saturation, a.temperature, a.highlights, a.shadows, a.sharpness, a.noiseReduction, a.vignette],
            effects: [subjectEffects.shadow, subjectEffects.outlineWidth],
            outlineColor: subjectEffects.outlineColor.srgbComponents,
            shapeID: shapePreset.id,
            freeform: shapePreset.freeform.map { $0.points.map { [Double($0.x), Double($0.y)] } },
            transform: .init(outputShapeTransform),
            text: text,
            logo: logo,
            selectedSubjectIDs: selectedSubjectIDs.map { Array($0).sorted() },
            hasMask: false,
            savedAt: Date()
        )

        let mask = (cachedMaskSource === original) ? cachedMask : nil
        return SessionStore.Input(
            session: session, original: original, mask: mask,
            logoImage: logoOverlay?.image, backgroundImage: backgroundImage
        )
    }

    // MARK: - Undo/redo

    private func currentSnapshot() -> EditSnapshot {
        EditSnapshot(
            backgroundStyle: backgroundStyle,
            photoFilter: photoFilter,
            imageAdjustments: imageAdjustments,
            shapePreset: shapePreset,
            subjectEffects: subjectEffects,
            outputShapeTransform: outputShapeTransform,
            textOverlay: textOverlay,
            logoOverlay: logoOverlay,
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
        var before = current
        before.outputShapeTransform = transform
        undoStack.append(before)
        redoStack.removeAll()
        updateUndoRedoAvailability()
    }

    private func updateUndoRedoAvailability() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        scheduleAutosave()
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
        shapePreset = snapshot.shapePreset
        subjectEffects = snapshot.subjectEffects
        outputShapeTransform = snapshot.outputShapeTransform
        lastCommittedTransform = snapshot.outputShapeTransform
        textOverlay = snapshot.textOverlay
        lastCommittedTextOverlay = snapshot.textOverlay
        logoOverlay = snapshot.logoOverlay
        lastCommittedLogoOverlay = snapshot.logoOverlay
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
            subjectCutoutImage = nil
            isProcessing = false
            // `refreshEditPreview()` uppdaterar `shareURL` själv numera när
            // dess async-beräkning blir klar - se dess dokumentationskommentar.
            refreshEditPreview()
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
