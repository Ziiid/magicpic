import SwiftUI

struct ContentView: View {
    @StateObject private var settings: SettingsStore
    @StateObject private var viewModel: SearchViewModel
    @State private var showSettings = false

    init() {
        let settingsStore = SettingsStore()
        _settings = StateObject(wrappedValue: settingsStore)
        _viewModel = StateObject(wrappedValue: SearchViewModel(settings: settingsStore))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            HStack(spacing: 0) {
                resultsGrid
                if viewModel.selectedItem != nil {
                    Divider()
                    DetailPanel(viewModel: viewModel)
                        .frame(width: 380)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
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
            .frame(width: 160)
            .labelsHidden()

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

            if viewModel.sourceKind == .web {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Unsplash API-inställningar")
            }
        }
        .padding(12)
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
}
