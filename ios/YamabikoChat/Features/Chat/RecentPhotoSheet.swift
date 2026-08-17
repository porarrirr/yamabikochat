import Photos
import SwiftUI
import UIKit

struct RecentPhotoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var library: RecentPhotoLibrary
    @Binding var selection: RecentPhotoSelection
    let isAdding: Bool
    let onAddSelected: () -> Void
    let onOpenFullLibrary: () -> Void

    private let columnSpacing: CGFloat = 4
    private let horizontalPadding: CGFloat = 12

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.chatScreenBackground
                    .ignoresSafeArea()

                if library.needsAuthorizationPrompt {
                    authorizationPromptView
                } else if library.isAccessDenied {
                    accessDeniedView
                } else if library.items.isEmpty && library.isLoading {
                    loadingView
                } else if library.items.isEmpty {
                    emptyView
                } else {
                    photosMasonryGrid(availableWidth: geometry.size.width)
                }

                floatingBottomBar
            }
        }
    }

    private func photosMasonryGrid(availableWidth: CGFloat) -> some View {
        let totalSpacing = columnSpacing * 2
        let totalPadding = horizontalPadding * 2
        let colWidth = max(40, (availableWidth - totalPadding - totalSpacing) / 3)

        let columns: [[RecentPhotoItem]] = {
            var cols: [[RecentPhotoItem]] = [[], [], []]
            var heights: [CGFloat] = [0, 0, 0]
            for item in library.items {
                let ratio = min(max(item.aspectRatio, 0.55), 1.85)
                let itemHeight = colWidth / ratio
                let minCol = heights.indices.min(by: { heights[$0] < heights[$1] }) ?? 0
                cols[minCol].append(item)
                heights[minCol] += itemHeight + columnSpacing
            }
            return cols
        }()

        return ScrollView(.vertical, showsIndicators: false) {
            HStack(alignment: .top, spacing: columnSpacing) {
                ForEach(0..<3, id: \.self) { colIndex in
                    LazyVStack(spacing: columnSpacing) {
                        ForEach(columns[colIndex]) { item in
                            let selectionIndex = selection.selectionIndex(for: item.id)
                            RecentPhotoMasonryCell(
                                item: item,
                                width: colWidth,
                                selectionIndex: selectionIndex,
                                isSelectionDisabled: isAdding || (selection.isAtLimit && selectionIndex == nil),
                                onTap: {
                                    triggerSelectionHaptic()
                                    _ = selection.toggle(item.id)
                                }
                            )
                        }
                    }
                    .frame(width: colWidth)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 88)
        }
    }

    private var floatingBottomBar: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [
                    Color.chatScreenBackground.opacity(0),
                    Color.chatScreenBackground.opacity(0.85),
                    Color.chatScreenBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 84)
            .allowsHitTesting(false)

            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color(white: 0.18, opacity: 0.85))
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("戻る"))

                Spacer()

                if selection.isEmpty {
                    Button {
                        onOpenFullLibrary()
                    } label: {
                        Text(L10n.text("すべての写真"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(Color(white: 0.18, opacity: 0.85))
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.22), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(isAdding)
                } else {
                    Button {
                        onAddSelected()
                    } label: {
                        HStack(spacing: 6) {
                            if isAdding {
                                ProgressView()
                                    .tint(.white)
                                    .controlSize(.small)
                            }
                            Text(selection.count == 1
                                ? L10n.text("1点の写真を追加する")
                                : L10n.format("%d点の写真を追加する", selection.count))
                                .font(.subheadline.weight(.bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.chatAccent)
                        .clipShape(Capsule())
                        .shadow(color: Color.chatAccent.opacity(0.4), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                    .disabled(isAdding)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    private var authorizationPromptView: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.stack")
                .font(.system(size: 40))
                .foregroundStyle(Color.chatAccent)

            Text(L10n.text("写真へのアクセスを許可"))
                .font(.headline)
                .foregroundStyle(Color.chatComposerText)

            Text(L10n.text("最近の写真をプレビューしてチャットにすぐ添付できます。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(L10n.text("アクセスを許可")) {
                library.requestAuthorization()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }

    private var accessDeniedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.stack")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(L10n.text("写真へのアクセスが許可されていません"))
                .font(.headline)
                .foregroundStyle(Color.chatComposerText)

            Text(L10n.text("「設定」アプリからYamabikoChatの写真アクセスを許可してください。"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(L10n.text("設定を開く")) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text(L10n.text("最近の写真を読み込み中..."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }

    private var emptyView: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text(L10n.text("写真が見つかりません"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Button(L10n.text("すべての写真")) {
                onOpenFullLibrary()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 60)
    }

    private func triggerSelectionHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}

private struct RecentPhotoMasonryCell: View {
    @Environment(\.displayScale) private var displayScale
    let item: RecentPhotoItem
    let width: CGFloat
    let selectionIndex: Int?
    let isSelectionDisabled: Bool
    let onTap: () -> Void

    @State private var image: UIImage?

    private var height: CGFloat {
        let ratio = min(max(item.aspectRatio, 0.55), 1.85)
        return width / ratio
    }

    var body: some View {
        Button {
            onTap()
        } label: {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle()
                            .fill(Color.chatInputChipBackground)
                            .overlay {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                    }
                }
                .frame(width: width, height: height)
                .clipped()

                if selectionIndex != nil {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.chatAccent, lineWidth: 2.5)
                }

                if let selectionIndex {
                    ZStack {
                        Circle()
                            .fill(Color.chatAccent)
                        Circle()
                            .stroke(.white, lineWidth: 1.5)
                        Text("\(selectionIndex)")
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                    .padding(6)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isSelectionDisabled && selectionIndex == nil ? 0.4 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selectionIndex)
        }
        .buttonStyle(.plain)
        .disabled(isSelectionDisabled && selectionIndex == nil)
        .task(id: item.id) {
            if image == nil {
                let targetSize = CGSize(width: width * displayScale, height: height * displayScale)
                image = await RecentPhotoThumbnailCache.shared.thumbnail(
                    for: item.asset,
                    targetSize: targetSize
                )
            }
        }
    }
}
