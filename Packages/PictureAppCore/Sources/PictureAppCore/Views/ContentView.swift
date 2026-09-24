import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

public struct ContentView: View {
    @StateObject private var settings: SettingsStore
    @StateObject private var viewModel: SearchViewModel
    @State private var showSettings = false
    @State private var isDropTargeted = false
    @State private var showImageSourceDialog = false
    @State private var showPhotosPicker = false
    @State private var photosPickerItem: PhotosPickerItem?
    @State private var showCamera = false

    public init(exporter: ImageExporter) {
        let settingsStore = SettingsStore()
        _settings = StateObject(wrappedValue: settingsStore)
        _viewModel = StateObject(wrappedValue: SearchViewModel(settings: settingsStore, exporter: exporter))
    }

    public var body: some View {
        platformLayout
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings)
            }
            .confirmationDialog("Välj bildkälla", isPresented: $showImageSourceDialog, titleVisibility: .visible) {
                Button("Från Foton") { showPhotosPicker = true }
                Button("Ta en bild") { showCamera = true }
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
                  let image = PlatformImage(data: data) else {
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
            .frame(width: 220)
            .labelsHidden()

            if viewModel.sourceKind == .web {
                TextField("Sök efter bilder…", text: $viewModel.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { viewModel.search() }

                Button {
                    viewModel.search()
                } label: {
                    if viewModel.isSearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                    }
                }
                .disabled(viewModel.isSearching)

                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Unsplash API-inställningar")
            } else {
                Spacer()

                Button {
                    showImageSourceDialog = true
                } label: {
                    Label("Välj bild…", systemImage: "photo.badge.plus")
                }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            if viewModel.sourceKind == .web {
                resultsGrid
            } else {
                ownImagePlaceholder
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
        .onDrop(
            of: [UTType.fileURL.identifier, UTType.url.identifier, UTType.image.identifier],
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

    private var resultsGrid: some View {
        ScrollView {
            if let error = viewModel.errorMessage, viewModel.results.isEmpty {
                Text(error)
                    .foregroundStyle(.secondary)
                    .padding()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                ForEach(viewModel.results) { item in
                    ResultThumbnail(item: item, isSelected: viewModel.selectedItem == item)
                        .onTapGesture { viewModel.select(item) }
                }
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Tar emot en bild som dragits in från Finder, Bilder eller en
    /// webbläsare, och skickar den vidare för bearbetning precis som ett
    /// sökresultat.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                guard let url = Self.url(from: item) else { return }
                Task { @MainActor in await viewModel.loadImportedImage(from: url) }
            }
            return true
        }

        if provider.canLoadObject(ofClass: PlatformImage.self) {
            // Utan casten till `NSItemProviderReading.Type` väljer Swift
            // felaktigt en annan `loadObject`-overload (för Objective-C-
            // brygade värdetyper som String/URL) som PlatformImage inte
            // uppfyller, och bygget misslyckas med ett förvirrande
            // `_ObjectiveCBridgeable`-fel.
            _ = provider.loadObject(ofClass: PlatformImage.self as NSItemProviderReading.Type) { reading, _ in
                guard let image = reading as? PlatformImage else { return }
                Task { @MainActor in viewModel.loadImportedImage(image, name: "Importerad bild") }
            }
            return true
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                guard let url = Self.url(from: item) else { return }
                Task { @MainActor in await viewModel.loadImportedImage(from: url) }
            }
            return true
        }

        return false
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        return nil
    }
}
