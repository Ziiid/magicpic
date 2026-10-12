import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

public struct ContentView: View {
    @StateObject private var viewModel: SearchViewModel
    @Environment(\.openURL) private var openURL
    @State private var isDropTargeted = false
    @State private var showImageSourceDialog = false
    @State private var showPhotosPicker = false
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showSettings = false
    @State private var showOnboarding = false
    // Sätts till `true` när introduktionen setts (eller hoppats över) - visas
    // bara första gången; kan öppnas igen från Inställningar.
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    // Appens EGET mörkt/ljust-läge, oberoende av systemets - `nil`-läget
    // ("följ systemet") finns medvetet INTE med; användaren bad om EN
    // switch (på/av), inte en tredelad väljare.
    @AppStorage("useDarkMode") private var useDarkMode = false
    // Default ENGELSKA - se `AppLanguage`s dokumentation för varför.
    @AppStorage("appLanguage") private var appLanguage: AppLanguage = .english
    // Användartillagda AI-bildgeneratorer (namn + URL) - se `SettingsView`
    // och `AIImageGenerator`. Sparas som JSON via `AIImageGeneratorList`
    // eftersom `@AppStorage` inte stödjer en array av `Codable`-structar
    // direkt.
    @AppStorage("aiImageGenerators") private var generatorsList = AIImageGeneratorList()

    public init(exporter: ImageExporter) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(exporter: exporter))
    }

    public var body: some View {
        platformLayout
            .task { await viewModel.refreshSavedSessionAvailability() }
            .onAppear {
                if !hasSeenOnboarding { showOnboarding = true }
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingView {
                    hasSeenOnboarding = true
                    showOnboarding = false
                }
            }
            .preferredColorScheme(useDarkMode ? .dark : .light)
            .environment(\.locale, appLanguage.locale)
            .confirmationDialog(L("Välj bildkälla"), isPresented: $showImageSourceDialog, titleVisibility: .visible) {
                Button(L("Från Foton")) { showPhotosPicker = true }
                Button(L("Ta en bild")) { showCamera = true }
                Button(L("Klistra in bild")) { viewModel.pasteFromClipboard() }
                Button(L("Avbryt"), role: .cancel) {}
            }
            .photosPicker(isPresented: $showPhotosPicker, selection: $photosPickerItem, matching: .images)
            .onChange(of: photosPickerItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    await loadPickedPhoto(newItem)
                    photosPickerItem = nil
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraCaptureView(
                    onCapture: { image in
                        viewModel.loadImportedImage(image, name: String(localized: "Kamera", bundle: .module, locale: AppLanguage.current.locale))
                        showCamera = false
                    },
                    onCancel: { showCamera = false }
                )
            }
    }

    @ViewBuilder
    private var platformLayout: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            searchBar
            Divider()
            HStack(spacing: 0) {
                mainContent
                if viewModel.selectedItem != nil {
                    Divider()
                    DetailPanel(viewModel: viewModel)
                        .frame(width: 380)
                }
            }
        }
        #else
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                Divider()
                mainContent
            }
            .navigationDestination(item: $viewModel.selectedItem) { _ in
                DetailPanel(viewModel: viewModel)
                    .navigationTitle(L("Förhandsvisning"))
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        #endif
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        let locale = AppLanguage.current.locale
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = PlatformImage.normalizedOrientation(from: data) else {
                viewModel.errorMessage = String(localized: "Kunde inte läsa den valda bilden.", bundle: .module, locale: locale)
                return
            }
            viewModel.loadImportedImage(image, name: String(localized: "Foto", bundle: .module, locale: locale))
        } catch {
            let prefix = String(localized: "Kunde inte läsa den valda bilden:", bundle: .module, locale: locale)
            viewModel.errorMessage = "\(prefix) \(error.localizedDescription)"
        }
    }

    /// Två rader i Webb/AI-läget: källväljare + inställningar överst, och
    /// sökfältet på EGEN rad i full bredd under (tidigare på samma rad som
    /// allt annat, vilket gav ett alldeles för litet sökfält i smala
    /// fönster - rapporterat 2026-10-10).
    private var searchBar: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("", selection: $viewModel.sourceKind) {
                    ForEach(ImageSourceKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                .labelsHidden()

                Spacer()

                if viewModel.sourceKind == .web {
                    Picker(L("Källa"), selection: $viewModel.searchEngine) {
                        ForEach(imageSources) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .foregroundStyle(.primary)
            }
            // `.buttonStyle(.plain)` uttryckligen - annars bleds systemets
            // accentfärg (blå) igenom trots `.foregroundStyle(.primary)` på
            // ikonen, samma bugg som Form/Format-knapparna hade (se
            // buggs.md 2026-09-26, "Blå text kvarstod på Form/Format").
            .buttonStyle(.plain)
            .help(L("Inställningar"))
            }

            if viewModel.sourceKind == .web {
                HStack {
                    TextField(L("Sök eller beskriv en bild…"), text: $viewModel.query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { openWebSearch() }

                    Button {
                        openWebSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .help(webSearchHelpText)
                }
            }
        }
        .padding(12)
        .sheet(isPresented: $showSettings) {
            SettingsView(useDarkMode: $useDarkMode, appLanguage: $appLanguage, generators: $generatorsList, onShowIntro: {
                showSettings = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showOnboarding = true }
            })
        }
    }

    /// Alla val i "Källa"-väljaren - de hårdkodade sökmotorerna (Google/
    /// Pinterest) följt av användarens egna AI-bildgeneratorer, tillagda i
    /// Inställningar.
    private var imageSources: [ImageSource] {
        WebSearchEngine.allCases.map(ImageSource.engine) + generatorsList.items.map(ImageSource.generator)
    }

    /// Tooltip på sök-knappen - skiljer sig per källa eftersom en AI-
    /// bildgenerator inte antas stödja drag (se `webSearchPlaceholder`/
    /// `buggs.md`), till skillnad från Google/Pinterest.
    private var webSearchHelpText: String {
        let locale = AppLanguage.current.locale
        if case .generator(let generator) = viewModel.searchEngine {
            let prefix = String(localized: "Öppnar", bundle: .module, locale: locale)
            let suffix = String(localized: "i webbläsaren - kräver att du är inloggad. Kopiera bilden där och klistra in den i appen (drag stöds kanske inte).", bundle: .module, locale: locale)
            return "\(prefix) \(generator.name) \(suffix)"
        }
        return String(localized: "Öppnar i webbläsaren - dra sedan in bilden du hittar i appen.", bundle: .module, locale: locale)
    }

    /// Instruktionstexten i `webSearchPlaceholder` för en AI-generator -
    /// generatorns namn är rådata (användaren har skrivit in det i
    /// Inställningar) och kan därför inte vara del av själva
    /// lokaliseringsnyckeln (se `CLAUDE.md`s regel om interpolerad data i
    /// lokaliserade strängar) - delas därför upp i en fast, lokaliserad
    /// prefix/suffix-text med namnet konkatenerat emellan.
    private func generatorInstructionText(for generator: AIImageGenerator) -> String {
        let locale = AppLanguage.current.locale
        let prefix = String(localized: "Skriv en bildbeskrivning ovan och tryck på förstoringsglaset -", bundle: .module, locale: locale)
        let suffix = String(localized: "öppnas i webbläsaren. Kräver att du är inloggad. Sidan kanske inte stödjer drag för bilder - högerklicka bilden, välj \"Kopiera bild\", och klistra in den nedan om det behövs.", bundle: .module, locale: locale)
        return "\(prefix) \(generator.name) \(suffix)"
    }

    /// Öppnar vald källa (sökmotor eller AI-bildgenerator) i systemets webbläsare
    /// med aktuell sökterm/prompt. Appen hämtar inga bilder själv härifrån
    /// - användaren hittar/skapar bilden i webbläsaren och drar in den i
    /// appen, vilket `.onDrop` på `mainContent` redan hanterar (fjärr-
    /// URL:er och rå bilddata, inte bara lokala filer).
    private func openWebSearch() {
        guard let url = viewModel.webSearchURL() else { return }
        openURL(url)
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            switch viewModel.sourceKind {
            case .web:
                webSearchPlaceholder
            case .ownImage:
                ownImagePlaceholder
            }
        }
        // Mörk XtraPic-bakgrund bakom alla tre tomtillstånden (egen bild/
        // urklipp/webb). Visas bara medan ingen bild är vald. Mörkt läge tvingas här så att
        // sekundärtexten förblir läsbar mot den mörka bilden även i ljust läge.
        .environment(\.colorScheme, .dark)
        .background {
            if viewModel.selectedItem == nil {
                // scaledToFit så hela X:et får plats; bildens nästan svarta
                // kant fortsätter i en matchande fyllnadsfärg.
                ZStack {
                    Color(white: 9.0 / 255.0)
                    Image("XtraPicBack")
                        .resizable()
                        .scaledToFit()
                }
            }
        }
        .clipped()
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(AppTheme.accent, lineWidth: 3)
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        // `UTType.item` (basroten alla typer ärver från) istället för en
        // snäv lista - en tidigare, snävare lista (bara fileURL/url/image)
        // riskerade att avvisa draget redan HÄR, innan `handleDrop` ens
        // kallades, om webbläsaren råkar annonsera en typidentifierare vi
        // inte förutsett (rapporterat 2026-09-25: en ChatGPT-genererad
        // bild gick inte att dra in från webbläsaren, trots att samma bild
        // gick fint från den fristående ChatGPT Mac-appen).
        .onDrop(
            of: [UTType.item.identifier],
            isTargeted: $isDropTargeted,
            perform: handleDrop
        )
    }

    private var ownImageHintText: String {
        #if os(iOS)
        L("Välj en bild från Foton eller ta en ny med kameran.")
        #else
        L("Välj en bild från Foton, ta en ny med kameran, eller dra in en bildfil.")
        #endif
    }

    private var ownImagePlaceholder: some View {
        placeholderLayout {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(ownImageHintText)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        } bottom: {
            Button {
                showImageSourceDialog = true
            } label: {
                Label(L("Välj bild…"), systemImage: "photo.badge.plus")
            }
            .buttonStyle(.borderedProminent)

            // Återuppta senaste, automatiskt sparade redigeringen.
            if viewModel.hasSavedSession, viewModel.selectedItem == nil {
                HStack(spacing: 12) {
                    Button {
                        Task { await viewModel.resumeSavedSession() }
                    } label: {
                        Label(L("Fortsätt där du slutade"), systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.bordered)

                    Button(L("Kasta sparad redigering")) {
                        Task { await viewModel.discardSavedSession() }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Gemensam layout för de tre tomtillstånden: symbol + förklarande text
    /// precis OVANFÖR bakgrundens X, åtgärdsknappen (och ev. felmeddelande)
    /// precis UNDER det, och mitten fri så X:et syns ograverat. Luckan i
    /// mitten räknas ut från hur stort X:et faktiskt ritas (bakgrundsbilden
    /// är 3:2, `scaledToFit`, och X:et upptar ca 58 % av bildens höjd), så
    /// texten/knappen följer X:et istället för att sitta längst ut i kanterna.
    private func placeholderLayout<Top: View, Bottom: View>(
        @ViewBuilder top: () -> Top,
        @ViewBuilder bottom: () -> Bottom
    ) -> some View {
        // Byggs FÖRE `GeometryReader` - dess closure är escaping och får
        // inte fånga de icke-escapande `top`/`bottom`-parametrarna.
        let topContent = top()
        let bottomContent = bottom()
        return GeometryReader { geo in
            let imageHeight = min(geo.size.height, geo.size.width / 1.5)
            // + 2 × 72 pt (ca 2 cm) luft mellan X:et och text/knapp.
            let xGap = imageHeight * 0.58 + 144
            // Luckan för X:et ligger EXAKT i mitten (bakgrundsbilden är
            // centrerad) - över- och underdelen får lika höga fält som
            // förankrar innehållet mot luckan, annars skulle ojämnt hög
            // text/knapp skjuta luckan ur läge och lägga texten på X:et.
            let half = max(0, (geo.size.height - xGap) / 2)
            VStack(spacing: 0) {
                VStack(spacing: 12) { topContent }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .frame(height: half)
                Color.clear.frame(height: xGap)
                VStack(spacing: 12) {
                    bottomContent
                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .frame(height: half)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// Visas i "Webb"-läget istället för ett inbäddat resultatrutnät -
    /// sökningen/genereringen öppnas i systemets webbläsare (se
    /// `openWebSearch()`) så man får riktiga sökresultat eller en riktig
    /// AI-genererad bild, utan API-nyckel; bilden man hittar/skapar dras
    /// sedan in hit, vilket `.onDrop` på `mainContent` redan hanterar -
    /// UTOM för AI-bildgeneratorer, vars sida vi inte kan anta stödjer
    /// drag för bilder (se `handleDrop` och `buggs.md`, tidigare bekräftat
    /// för ChatGPT specifikt), så en egen "Klistra in bild"-knapp visas
    /// HÄR bara när en AI-generator är vald källa (annars är den bara
    /// förvirrande brus för Google/Pinterest, där drag redan fungerar).
    /// Förklaringstext för Google/Pinterest - på iPhone finns inget drag
    /// från webbläsaren till appen, så där hänvisas till kopiera/klistra in.
    private var webSearchHintText: String {
        #if os(iOS)
        L("Skriv en sökning ovan, välj Google eller Pinterest och tryck på förstoringsglaset - det öppnas i webbläsaren. Kopiera bilden du hittar och klistra in den här.")
        #else
        L("Skriv en sökning ovan, välj Google eller Pinterest och tryck på förstoringsglaset - det öppnas i webbläsaren. Dra in bilden du hittar direkt hit.")
        #endif
    }

    private var webSearchPlaceholder: some View {
        placeholderLayout {
            Image(systemName: "globe")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            if case .generator(let generator) = viewModel.searchEngine {
                Text(generatorInstructionText(for: generator))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            } else {
                Text(webSearchHintText)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        } bottom: {
            // Alltid synlig (Urklipp-fliken är borttagen) - klistra in är
            // enda vägen på iPhone och reservvägen på Mac.
            Button {
                viewModel.pasteFromClipboard()
            } label: {
                Label(L("Klistra in bild"), systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("v", modifiers: .command)
        }
    }

    /// Tar emot en bild som dragits in från Finder, Bilder eller en
    /// webbläsare, och skickar den vidare för bearbetning precis som ett
    /// sökresultat.
    ///
    /// Startar ALLA rimliga representationstyper (bildobjekt via
    /// `loadObject`, rå bilddata via `loadDataRepresentation`, fil-URL,
    /// vanlig URL) SAMTIDIGT, och den som faktiskt svarar FÖRST med ett
    /// giltigt resultat vinner (`DropClaim` ser till att bara en av dem
    /// faktiskt importerar bilden) - en hängande callback för en typ (t.ex.
    /// ett Safari-"fil-löfte", `NSFilePromiseReceiver`-protokollet, som kan
    /// hänga sig helt utan att någonsin svara) blockerar då inte de andra.
    /// `.onDrop` ovan tar dessutom emot VILKEN typ som helst (`UTType.item`)
    /// istället för en snäv lista, så draget avvisas aldrig redan där.
    ///
    /// Trots detta: en ChatGPT-genererad bild gick 2026-09-25 fortfarande
    /// INTE att dra in från webbläsaren (Safari/Chrome), trots att SAMMA
    /// bild fungerade dragen från den fristående ChatGPT Mac-appen, och
    /// trots att "Kopiera bild" + "Klistra in bild"
    /// (`PlatformImage.fromPasteboard()`) fungerar perfekt för samma bild.
    /// Det tyder på att webbläsarens drag för just den bilden inte
    /// annonserar NÅGON av typerna vi letar efter alls (native
    /// Mac-appar ger normalt renare/enklare representationer än en
    /// webbsidas drag-session gör). Om inget av försöken nedan lyckas
    /// inom 2 sekunder visas därför `provider.registeredTypeIdentifiers`
    /// som ett diagnostiskt felmeddelande - så nästa fix kan byggas mot
    /// vad webbläsaren FAKTISKT erbjuder istället för att gissa igen.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        let claim = DropClaim()

        if provider.canLoadObject(ofClass: PlatformImage.self) {
            // Utan casten till `NSItemProviderReading.Type` väljer Swift
            // felaktigt en annan `loadObject`-overload (för Objective-C-
            // brygade värdetyper som String/URL) som PlatformImage inte
            // uppfyller, och bygget misslyckas med ett förvirrande
            // `_ObjectiveCBridgeable`-fel.
            _ = provider.loadObject(ofClass: PlatformImage.self as NSItemProviderReading.Type) { reading, _ in
                guard let image = reading as? PlatformImage, claim.tryClaim() else { return }
                Task { @MainActor in viewModel.loadImportedImage(image.normalizedOrientation(), name: String(localized: "Importerad bild", bundle: .module, locale: AppLanguage.current.locale)) }
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            // Lägre nivå än `loadObject(ofClass:)` ovan - ber bara om RÅ
            // bilddata för valfri typ som konformerar till `public.image`,
            // utan att bero på att NSImage/UIImage själva känner igen
            // exakt den identifieraren som "läsbar". Ett annat nät under
            // `canLoadObject`-vägen ovan.
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                guard let data, let decoded = PlatformImage(data: data), claim.tryClaim() else { return }
                Task { @MainActor in viewModel.loadImportedImage(decoded.normalizedOrientation(), name: String(localized: "Importerad bild", bundle: .module, locale: AppLanguage.current.locale)) }
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let url = Self.url(from: item), claim.tryClaim() else { return }
                Task { @MainActor in await viewModel.loadImportedImage(from: url) }
            }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                guard let url = Self.url(from: item), claim.tryClaim() else { return }
                Task { @MainActor in await viewModel.loadImportedImage(from: url) }
            }
        }

        // Bekräftat 2026-09-26 (diagnostikmeddelandet nedan avslöjade det):
        // en bild dragen från ChatGPTs webbsida annonserar VARKEN bildobjekt,
        // fil-URL eller vanlig URL - bara `com.apple.WebKit.custom-
        // pasteboard-data` (sidans EGEN, JavaScript-byggda dragpayload,
        // `dataTransfer.setData(...)` med en egen datatyp istället för att
        // låta webbläsaren dra själva bilden). Det är ett opakt,
        // sidinternt format som ingen app utanför sidan kan tolka - inget
        // vi kan koda oss runt här, till skillnad från Google Bildsök/
        // Pinterest som drar en vanlig, dragbar bild. "Klistra in"-knappen
        // (som går via "Kopiera bild" i webbläsaren, INTE sidans
        // dragkod) är den korrekta, permanenta lösningen för just den
        // sortens sida.
        let registeredTypes = provider.registeredTypeIdentifiers
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            Task { @MainActor in
                guard !claim.isClaimed else { return }
                viewModel.errorMessage = String(
                    localized: "Den här bilden går inte att dra in direkt - webbsidan levererar bilddata på ett sätt appen inte kan läsa. Högerklicka bilden i webbläsaren, välj \"Kopiera bild\", och använd \"Klistra in bild\" under Webb/AI istället.",
                    bundle: .module,
                    locale: AppLanguage.current.locale
                )
                #if DEBUG
                print("[handleDrop] Kunde inte tolka draget. Annonserade typer: \(registeredTypes)")
                #endif
            }
        }

        return true
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        return nil
    }
}

/// Ser till att bara EN av de parallella drop-representationsförsöken i
/// `ContentView.handleDrop` faktiskt importerar bilden, även om flera
/// skulle lyckas (eller svara sent). Låst med `NSLock` eftersom
/// callbacken för varje representationstyp kan komma tillbaka på olika,
/// godtyckliga bakgrundstrådar.
private final class DropClaim {
    private var claimed = false
    private let lock = NSLock()

    var isClaimed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return claimed
    }

    func tryClaim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
