import SwiftUI

struct ClipboardRowView: View {
    let item: ClipboardItem
    let isSelected: Bool
    let isHovering: Bool
    var onEdit: (() -> Void)?

    @AppStorage(Constants.hidePasswordsKey) private var hidePasswords = true

    private var isSensitive: Bool {
        hidePasswords && item.looksLikePassword
    }

    var body: some View {
        HStack(spacing: 10) {
            contentIcon
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                if isSensitive {
                    Text("••••••••")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(isSelected ? .white.opacity(0.6) : .secondary)
                } else {
                    Text(item.title)
                        .font(.system(size: 13))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .foregroundStyle(isSelected ? .white : .primary)
                }

                HStack(spacing: 4) {
                    if isSensitive {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(isSelected ? .white.opacity(0.7) : .orange)
                        Text("Sensitive")
                            .font(.system(size: 10))
                            .foregroundStyle(isSelected ? .white.opacity(0.7) : .orange)
                    } else if let appName = item.sourceAppName {
                        Text(appName)
                            .font(.system(size: 10))
                            .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
                    }
                }
            }

            Spacer()

            if item.isEditable, isSelected || isHovering {
                Button {
                    onEdit?()
                } label: {
                    // The glyph itself renders at 13pt, unchanged; the frame + explicit
                    // content shape below only widen the *hit target* around it. Without
                    // this, a near-miss click falls through to the row's onTapGesture and
                    // pastes into the frontmost app — the most startling near-miss outcome
                    // anywhere in this UI, so the pencil gets a comfortably larger target
                    // than its glyph.
                    Image(systemName: "pencil.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Edit")
            }

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .orange)
            }

            if item.numberOfCopies > 1 {
                Text("\(item.numberOfCopies)")
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.white.opacity(0.3) : Color.secondary.opacity(0.15))
                    )
                    .foregroundStyle(isSelected ? .white : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : (isHovering ? Color.secondary.opacity(0.08) : Color.clear))
                .padding(.horizontal, 4)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var contentIcon: some View {
        if isSensitive {
            iconView(systemName: "lock.shield")
        } else {
            switch item.primaryType {
            case .image:
                if let image = item.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 32, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                } else {
                    iconView(systemName: "photo")
                }
            case .fileURL:
                iconView(systemName: "doc")
            case .rtf:
                iconView(systemName: "doc.richtext")
            case .html:
                iconView(systemName: "globe")
            case .text:
                iconView(systemName: "doc.text")
            }
        }
    }

    private func iconView(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 16))
            .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
            .frame(width: 32, height: 32)
    }
}
