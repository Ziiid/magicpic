import SwiftUI

/// Filterväljare - ett rutnät med förhandsvisningsminiatyrer (samma bild,
/// varje färdig stil tillämpad) att trycka på. Ett tryck väljer filtret
/// direkt (ingen "Klar"-bekräftelse behövs för själva valet, precis som
/// reglagen i `ImageAdjustmentsView`).
///
/// Miniatyrerna genereras EN gång från en nedskalad kopia av bilden
/// (`PlatformImage.resized(maxDimension:)`) - att köra nio CoreImage-filter
/// i full upplösning bara för förhandsvisningar vore onödigt kostsamt.
struct PhotoFilterPickerView: View {
    let baseImage: PlatformImage
    let currentFilter: PhotoFilter
    let onSelect: (PhotoFilter) -> Void
    let onDone: () -> Void

    @State private var thumbnails: [PhotoFilter: PlatformImage] = [:]

    var body: some View {
        VStack(spacing: 16) {
            Text("Filter")
                .font(.headline)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 12)], spacing: 16) {
                    ForEach(PhotoFilter.allCases) { filter in
                        Button {
                            onSelect(filter)
                        } label: {
                            VStack(spacing: 6) {
                                thumbnailView(for: filter)
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(filter == currentFilter ? AppTheme.accent : Color.secondary.opacity(0.2), lineWidth: filter == currentFilter ? 3 : 1)
                                    )
                                Text(filter.label)
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
            }

            HStack {
                Spacer()
                Button("Klart") { onDone() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 340, idealWidth: 400, minHeight: 420, idealHeight: 480)
        .task { await generateThumbnails() }
    }

    @ViewBuilder
    private func thumbnailView(for filter: PhotoFilter) -> some View {
        if let thumbnail = thumbnails[filter] {
            Image(platformImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.15))
                .overlay(ProgressView().controlSize(.small))
        }
    }

    private func generateThumbnails() async {
        let filterService = PhotoFilterService()
        let small = baseImage.resized(maxDimension: 160)
        for filter in PhotoFilter.allCases {
            guard let result = try? filterService.apply(filter, to: small) else { continue }
            thumbnails[filter] = result
        }
    }
}
