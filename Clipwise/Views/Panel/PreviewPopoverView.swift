import SwiftUI

struct PreviewPopoverView: View {
    let item: ClipboardItem

    /// Max height = 1/3 of screen height
    private var maxHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        return screenHeight / 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: item.primaryType.systemImage)
                    .foregroundStyle(.secondary)
                Text(item.primaryType.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let text = item.plainText {
                    Text("\(text.count) chars")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
            }

            Divider()

            // Content preview
            Group {
                switch item.primaryType {
                case .image:
                    imagePreview
                case .fileURL:
                    filePreview
                default:
                    textPreview
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(12)
        .frame(maxHeight: maxHeight)
    }

    @ViewBuilder
    private var textPreview: some View {
        if item.looksLikePassword {
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
                Text("Sensitive content hidden")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        } else if let text = item.plainText {
            ScrollView(.vertical) {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 4)
            }
        } else {
            Text("No preview available")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image = item.image {
            VStack(alignment: .leading, spacing: 6) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: maxHeight - 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("\(Int(image.size.width)) × \(Int(image.size.height)) px")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary.opacity(0.6))
            }
        }
    }

    @ViewBuilder
    private var filePreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(item.fileURLs, id: \.absoluteString) { url in
                HStack(spacing: 6) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(url.lastPathComponent)
                            .font(.system(size: 12))
                            .lineLimit(1)
                        Text(url.deletingLastPathComponent().path)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            }
        }
    }
}
