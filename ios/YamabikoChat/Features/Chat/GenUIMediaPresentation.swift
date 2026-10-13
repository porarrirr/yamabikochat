import SwiftUI

struct GenUIImagePresentation: Identifiable {
    struct Image { let url: URL; let title: String }
    let id = UUID()
    let images: [Image]
    let selected: Int
}

struct GenUIImagePresentationView: View {
    let presentation: GenUIImagePresentation
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int

    init(presentation: GenUIImagePresentation) {
        self.presentation = presentation
        _selection = State(initialValue: presentation.selected)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(Array(presentation.images.enumerated()), id: \.offset) { index, image in
                    VStack(spacing: 16) {
                        AsyncImage(url: image.url) { phase in
                            switch phase {
                            case .success(let image): GenUIZoomableImage(image: image)
                            case .failure: ContentUnavailableView(L10n.text("画像を読み込めません"), systemImage: "photo")
                            default: ProgressView()
                            }
                        }
                        Text(image.title).font(.caption).foregroundStyle(.secondary)
                    }.padding().tag(index)
                }
            }
            .tabViewStyle(.page)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("閉じる")) { dismiss() } } }
        }
    }
}

private struct GenUIZoomableImage: View {
    let image: SwiftUI.Image
    @State private var scale: CGFloat = 1
    @State private var offset = CGSize.zero
    @GestureState private var magnification: CGFloat = 1
    @GestureState private var translation = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            image.resizable().scaledToFit()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(min(6, max(1, scale * magnification)))
                .offset(x: offset.width + translation.width, y: offset.height + translation.height)
                .gesture(MagnifyGesture()
                    .updating($magnification) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        scale = min(6, max(1, scale * value.magnification))
                        offset = clamped(offset, size: geometry.size)
                    })
                .simultaneousGesture(DragGesture()
                    .updating($translation) { value, state, _ in if scale > 1 { state = value.translation } }
                    .onEnded { value in
                        guard scale > 1 else { return }
                        offset = clamped(CGSize(width: offset.width + value.translation.width,
                                                height: offset.height + value.translation.height), size: geometry.size)
                    })
                .onTapGesture(count: 2) { withAnimation { scale = scale > 1 ? 1 : 2; offset = .zero } }
                .accessibilityAction(named: Text("Zoom")) { scale = scale > 1 ? 1 : 2; offset = .zero }
        }.clipped()
    }

    private func clamped(_ value: CGSize, size: CGSize) -> CGSize {
        let x = size.width * (scale - 1) / 2, y = size.height * (scale - 1) / 2
        return CGSize(width: min(x, max(-x, value.width)), height: min(y, max(-y, value.height)))
    }
}

struct GenUISharePresentation: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct GenUISharePresentationView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
