import SwiftUI

struct ResultThumbnail: View {
    let item: SearchResultItem
    let isSelected: Bool

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
    }

    @ViewBuilder
    private var content: some View {
        if let url = item.thumbnailURL {
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
