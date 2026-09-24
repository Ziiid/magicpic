import SwiftUI

struct DetailPanel: View {
    @ObservedObject var viewModel: SearchViewModel

    var body: some View {
        VStack(spacing: 12) {
            ScrollView {
                if viewModel.isLoadingDetail {
                    ProgressView("Laddar bild…")
                        .padding(40)
                } else if let image = viewModel.processedImage ?? viewModel.originalImage {
                    Image(nsImage: image)
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
                        Label("Ta bort bakgrund", systemImage: "person.crop.rectangle.badge.xmark")
                    }
                }
                .disabled(viewModel.originalImage == nil || viewModel.isProcessing)

                Button {
                    viewModel.save()
                } label: {
                    Label("Spara", systemImage: "square.and.arrow.down")
                }
                .disabled(viewModel.originalImage == nil)
            }
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity)
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
