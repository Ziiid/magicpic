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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    // Ingen egen "Ta bort bakgrund"-knapp - "Ingen
                    // (genomskinlig)" under Bakgrund-menyn gör exakt samma
                    // sak, en egen knapp för det var bara en dubblett
                    // (rapporterat 2026-09-25).
                    if viewModel.isProcessing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Bearbetar…")
                        }
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    }

                    Button {
                        viewModel.restoreOriginal()
                    } label: {
                        Label("Återställ", systemImage: "arrow.uturn.backward")
                    }
                    .disabled(!hasChanges)
                    .help("Kasta bakgrunds-/form-/positioneringsval och gå tillbaka till originalbilden.")

                    backgroundMenu

                    shapeMenu

                    Button {
                        showPhotoFilters = true
                    } label: {
                        Label("Filter", systemImage: "camera.filters")
                    }
                    .disabled(viewModel.originalImage == nil)
                    .help("Färdiga bildstilar - svartvitt, sepia, röntgen, m.fl.")

                    Button {
                        showAdjustments = true
                    } label: {
                        Label("Justera", systemImage: "slider.horizontal.3")
                    }
                    .disabled(viewModel.originalImage == nil)
                    .help("Ljusstyrka, kontrast, mättnad, skärpa, temperatur, highlights/shadows, brusreducering, vinjett.")

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
                                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: isSelectedColor(color) ? 3 : 0))
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
