import SwiftUI

struct ResultThumbnail: View {
    let item: SearchResultItem
    let isSelected: Bool
    @State private var localImage: NSImage?

    private let photosService = PhotosSearchService()

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                content
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .frame(width: 140, height: 100)

            Text(item.title)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.secondary)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .task(id: item.id) {
            if let asset = item.localAsset {
                localImage = await photosService.loadImage(for: asset, targetSize: CGSize(width: 280, height: 200))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if item.localAsset != nil {
            if let localImage {
                Image(nsImage: localImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView().controlSize(.small)
            }
        } else if let url = item.thumbnailURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    Image(systemName: "photo").foregroundStyle(.secondary)
                default:
                    ProgressView().controlSize(.small)
                }
            }
        } else {
            Image(systemName: "photo")
        }
    }
}
