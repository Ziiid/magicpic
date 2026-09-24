import SwiftUI
import UniformTypeIdentifiers

struct DetailPanel: View {
    @ObservedObject var viewModel: SearchViewModel
    @State private var showBackgroundImporter = false
    @State private var showColorPicker = false

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                if viewModel.isLoadingDetail {
                    ProgressView("Laddar bild…")
                        .padding(40)
                } else if let image = viewModel.processedImage ?? viewModel.originalImage {
                    Image(platformImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .background(CheckerboardBackground())
                        .cornerRadius(8)
                        .padding()
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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button {
                        viewModel.removeBackground()
                    } label: {
                        if viewModel.isProcessing {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Bearbetar…")
                            }
                        } else {
                            Label(
                                viewModel.processedImage == nil ? "Ta bort bakgrund" : "Uppdatera",
                                systemImage: "person.crop.rectangle.badge.xmark"
                            )
                        }
                    }
                    .disabled(viewModel.originalImage == nil || viewModel.isProcessing)

                    backgroundMenu

                    shapeMenu

                    Button {
                        viewModel.beginMaskEditing()
                    } label: {
                        Label("Finjustera", systemImage: "paintbrush.pointed")
                    }
                    .disabled(viewModel.processedImage == nil)
                    .help("Måla för hand för att lägga till eller ta bort delar av urklippet.")

                    Button {
                        viewModel.save()
                    } label: {
                        Label("Spara", systemImage: "square.and.arrow.down")
                    }
                    .disabled(viewModel.originalImage == nil)
                }
                .padding(.horizontal, 2)
            }
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity)
        .fileImporter(isPresented: $showBackgroundImporter, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                Task { await viewModel.setCustomBackground(from: url) }
            case .failure(let error):
                viewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $viewModel.backgroundPositioningRequest) { request in
            BackgroundPositionerView(
                image: request.image,
                previewAspectRatio: previewAspectRatio,
                initialTransform: request.initialTransform,
                onDone: { transform in viewModel.confirmCustomBackground(image: request.image, transform: transform) },
                onCancel: { viewModel.cancelCustomBackgroundPositioning() }
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
        .sheet(isPresented: $showColorPicker) {
            VStack(spacing: 20) {
                Text("Bakgrundsfärg")
                    .font(.headline)

                ColorPicker(
                    "Färg",
                    selection: Binding(
                        get: {
                            if case .color(let color) = viewModel.backgroundStyle { return color }
                            return .white
                        },
                        set: { viewModel.setBackgroundStyle(.color($0)) }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()

                HStack {
                    Spacer()
                    Button("Klart") { showColorPicker = false }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(minWidth: 280, minHeight: 160)
        }
    }

    private var previewAspectRatio: CGFloat {
        guard let size = viewModel.originalImage?.size, size.width > 0, size.height > 0 else { return 1 }
        return size.width / size.height
    }

    private var hasCustomBackground: Bool {
        if case .custom = viewModel.backgroundStyle { return true }
        return false
    }

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
            Label("Bakgrund", systemImage: "photo.on.rectangle.angled")
        }
        .disabled(viewModel.originalImage == nil)
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
            Label("Form", systemImage: "square.on.circle")
        }
        .disabled(viewModel.originalImage == nil)
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
