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

    public init(exporter: ImageExporter) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(exporter: exporter))
    }

    public var body: some View {
        platformLayout
            .confirmationDialog("Välj bildkälla", isPresented: $showImageSourceDialog, titleVisibility: .visible) {
                Button("Från Foton") { showPhotosPicker = true }
                Button("Ta en bild") { showCamera = true }
                Button("Klistra in bild") { viewModel.pasteFromClipboard() }
                Button("Avbryt", role: .cancel) {}
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
                        viewModel.loadImportedImage(image, name: "Kamera")
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
                    .navigationTitle("Förhandsvisning")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        #endif
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = PlatformImage.normalizedOrientation(from: data) else {
                viewModel.errorMessage = "Kunde inte läsa den valda bilden."
                return
            }
            viewModel.loadImportedImage(image, name: "Foto")
        } catch {
            viewModel.errorMessage = "Kunde inte läsa den valda bilden: \(error.localizedDescription)"
        }
    }

    private var searchBar: some View {
        HStack {
            Picker("", selection: $viewModel.sourceKind) {
                ForEach(ImageSourceKind.allCases) { kind in
                    Text(kind.rawValue).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            .labelsHidden()

            if viewModel.sourceKind == .web {
                TextField("Sök eller beskriv en bild…", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { openWebSearch() }

                Picker("Källa", selection: $viewModel.searchEngine) {
                    ForEach(WebSearchEngine.allCases) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .labelsHidden()
                .frame(width: 130)

                Button {
                    openWebSearch()
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .help(webSearchHelpText)
            } else {
                Spacer()
            }
        }
        .padding(12)
    }

    /// Tooltip på sök-knappen - skiljer sig per källa eftersom ChatGPT
    /// inte stödjer drag (se `webSearchPlaceholder`/`buggs.md`), till
    /// skillnad från Google/Pinterest.
    private var webSearchHelpText: String {
        switch viewModel.searchEngine {
        case .chatGPT:
            return "Öppnar ChatGPT i webbläsaren - kräver att du är inloggad. Kopiera bilden där och klistra in den i appen (drag stöds inte)."
        case .google, .pinterest:
            return "Öppnar i webbläsaren - dra sedan in bilden du hittar i appen."
        }
    }

    /// Öppnar vald källa (sökmotor eller ChatGPT) i systemets webbläsare
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
            case .paste:
                pasteImagePlaceholder
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
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

    private var ownImagePlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Välj en bild från Foton, ta en ny med kameran, eller dra in en bildfil.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showImageSourceDialog = true
            } label: {
                Label("Välj bild…", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Visas i "Webb"-läget istället för ett inbäddat resultatrutnät -
    /// sökningen/genereringen öppnas i systemets webbläsare (se
    /// `openWebSearch()`) så man får riktiga sökresultat eller en riktig
    /// AI-genererad bild, utan API-nyckel; bilden man hittar/skapar dras
    /// sedan in hit, vilket `.onDrop` på `mainContent` redan hanterar -
    /// UTOM för ChatGPT, vars sida inte stödjer drag för bilder alls (se
    /// `handleDrop` och `buggs.md`), så en egen "Klistra in bild"-knapp
    /// visas HÄR bara när ChatGPT är vald källa (annars är den bara
    /// förvirrande brus för Google/Pinterest, där drag redan fungerar).
    private var webSearchPlaceholder: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image("AppLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

                Text("PictureApp")
                    .font(.title2.weight(.semibold))

                if viewModel.searchEngine == .chatGPT {
                    VStack(spacing: 6) {
                        Text("Skriv en bildbeskrivning ovan och tryck på förstoringsglaset - ChatGPT öppnas i webbläsaren. Kräver att du är inloggad. Sidan stödjer tyvärr inte drag för bilder - högerklicka bilden, välj \"Kopiera bild\", och klistra in den nedan.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)

                        Button {
                            viewModel.pasteFromClipboard()
                        } label: {
                            Label("Klistra in bild", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("v", modifiers: .command)
                    }
                } else {
                    Text("Skriv en sökning ovan, välj Google eller Pinterest och tryck på förstoringsglaset - det öppnas i webbläsaren. Dra in bilden du hittar direkt hit.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }
            .padding(.top, 60)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Egen flik för att klistra in en bild från urklipp - t.ex. en
    /// skärmbild, eller en bild kopierad från valfri app/webbsida. Låg
    /// tidigare gömd som en knapp inne i "Webb"-fliken (tänkt som
    /// reservväg när drag-and-drop inte fungerade från en webbsida), men
    /// hörde inte ihop med webbsökning konceptuellt och var därför inte
    /// intuitiv att hitta där (rapporterat 2026-09-26).
    private var pasteImagePlaceholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Klistra in en bild från urklipp - t.ex. en skärmbild, eller en bild du kopierat från en app eller webbsida.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                viewModel.pasteFromClipboard()
            } label: {
                Label("Klistra in bild", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut("v", modifiers: .command)

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                Task { @MainActor in viewModel.loadImportedImage(image.normalizedOrientation(), name: "Importerad bild") }
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
                Task { @MainActor in viewModel.loadImportedImage(decoded.normalizedOrientation(), name: "Importerad bild") }
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
        // Pinterest som drar en vanlig, dragbar bild. "Klistra in"-fliken
        // (som går via "Kopiera bild" i webbläsaren, INTE sidans
        // dragkod) är den korrekta, permanenta lösningen för just den
        // sortens sida.
        let registeredTypes = provider.registeredTypeIdentifiers
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            Task { @MainActor in
                guard !claim.isClaimed else { return }
                viewModel.errorMessage = "Den här bilden går inte att dra in direkt - webbsidan levererar bilddata på ett sätt appen inte kan läsa. Högerklicka bilden i webbläsaren, välj \"Kopiera bild\", och använd fliken \"Urklipp\" istället."
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
