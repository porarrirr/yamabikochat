import SwiftUI
import WebKit

private struct GenUINewTurnKey: EnvironmentKey {
    static let defaultValue: (String) -> Bool = { _ in false }
}

private struct GenUIPrefillKey: EnvironmentKey {
    static let defaultValue: (String) -> Void = { _ in }
}

private struct GenUIRouteKey: EnvironmentKey {
    static let defaultValue: (ChatWorkspaceRoute) -> Void = { _ in }
}

extension EnvironmentValues {
    var onGenUIPrefill: (String) -> Void {
        get { self[GenUIPrefillKey.self] }
        set { self[GenUIPrefillKey.self] = newValue }
    }

    var onGenUIRoute: (ChatWorkspaceRoute) -> Void {
        get { self[GenUIRouteKey.self] }
        set { self[GenUIRouteKey.self] = newValue }
    }

    var onGenUINewTurn: (String) -> Bool {
        get { self[GenUINewTurnKey.self] }
        set { self[GenUINewTurnKey.self] = newValue }
    }
}

struct GenUIRichView: View {
    let document: GenUIDocument
    @ObservedObject var state: GenUIState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.onGenUIPrefill) private var prefillComposer
    @Environment(\.onGenUINewTurn) private var issueNewTurn
    @Environment(\.openURL) private var openURL
    @State private var status: String?
    @State private var imagePresentation: GenUIImagePresentation?
    @State private var sharePresentation: GenUISharePresentation?
    @State private var videoPresentation: GenUIVideoPresentation?
    @Environment(\.onGenUIRoute) private var presentRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GenUIRichWebView(document: document, state: state, dark: colorScheme == .dark, height: $state.richHeight, onStatus: { status = $0 }, onAction: handle)
                .frame(height: state.richHeight)
                .accessibilityIdentifier("genui-rich-canvas")
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .accessibilityIdentifier("genui-rich-status")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The document owns its card hierarchy; avoid a second enclosing panel.
        .background(Color(uiColor: .systemBackground))
        .sheet(item: $imagePresentation) { GenUIImagePresentationView(presentation: $0) }
        .sheet(item: $sharePresentation) { GenUISharePresentationView(items: $0.items) }
        .sheet(item: $videoPresentation) { GenUIVideoPresentationView(presentation: $0) }
    }

    private func handle(_ object: [String: Any]) {
        DiagnosticsLogger.log("GenUI host action", category: .app, metadata: ["type": object["type"] as? String ?? "unknown"])
        switch object["type"] as? String {
        case "copy":
            guard let text = object["text"] as? String, text.utf8.count <= 65_536 else { return }
            UIPasteboard.general.string = text
            status = L10n.text("コピーしました")
        case "openUrl":
            guard let raw = object["url"] as? String, let url = GenUIHostPolicy.externalURL(raw) else {
                status = L10n.text("このリンクは開けません")
                return
            }
            openURL(url)
        case "prefillComposer":
            guard let text = object["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 16_384 else { return }
            prefillComposer(text)
        case "composeEmail":
            guard let args = object["args"] as? [String: Any], let email = args["email"] as? [String: Any],
                  let to = email["to"] as? String, !to.contains("\n"), !to.contains("\r") else { return }
            var draft = URLComponents()
            draft.scheme = "mailto"
            draft.path = to
            draft.queryItems = [URLQueryItem(name: "subject", value: email["subject"] as? String ?? ""),
                                URLQueryItem(name: "body", value: email["body"] as? String ?? "")]
            guard let url = draft.url else { return }
            openURL(url)
        case "issueNewTurn":
            guard let query = object["query"] as? String, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, query.utf8.count <= 16_384 else { return }
            status = issueNewTurn(query) ? nil : L10n.text("送信中の応答や入力欄の下書きを確認してください")
        case "openEntityDetail":
            presentRoute(.genUIEntity(GenUIEntityDetail(object["args"] as? [String: Any] ?? [:])))
        case "openImageLightbox":
            let args = object["args"] as? [String: Any] ?? [:]
            let images = (args["images"] as? [[String: Any]] ?? []).compactMap { item -> GenUIImagePresentation.Image? in
                guard let raw = item["image_url"] as? String ?? item["url"] as? String ?? item["src"] as? String,
                      let url = GenUIHostPolicy.externalURL(raw) else { return nil }
                return .init(url: url, title: item["alt_text"] as? String ?? item["title"] as? String ?? "")
            }
            guard !images.isEmpty else { status = L10n.text("表示できる画像がありません"); return }
            imagePresentation = .init(images: images, selected: min(max(args["selected_index"] as? Int ?? 0, 0), images.count - 1))
        case "openVideoLightbox":
            let args = object["args"] as? [String: Any] ?? [:]
            guard let id = args["video_id"] as? String, id.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else {
                status = L10n.text("この動画の参照には参考元のサービスが必要です")
                return
            }
            videoPresentation = .init(videoID: id, title: args["title"] as? String ?? "YouTube")
        case "share":
            let args = object["args"] as? [String: Any] ?? [:]
            let payload = args["share_options"] as? [String: Any] ?? args
            var items: [Any] = []
            if let text = payload["text"] as? String ?? payload["message"] as? String ?? payload["title"] as? String { items.append(text) }
            if let url = (payload["url"] as? String).flatMap(GenUIHostPolicy.externalURL) { items.append(url) }
            guard !items.isEmpty else { status = L10n.text("共有データには参考元サーバーが必要です"); return }
            sharePresentation = .init(items: items)
        case "openMap":
            guard let props = object["props"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: props),
                  let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data),
                  let configuration = GenUIMapConfiguration(props: decoded) else {
                status = L10n.text("地図には場所名・住所、または有効な緯度・経度を指定してください")
                return
            }
            presentRoute(.genUIMap(configuration))
            DiagnosticsLogger.log("GenUI map presentation requested", category: .app)
        default:
            status = L10n.text("この操作は利用できません")
        }
    }
}

struct GenUIEntityDetail: Identifiable {
    let id = UUID()
    var title: String
    var fields: [(String, String)]
    var url: URL?

    init(_ args: [String: Any]) {
        title = args["title"] as? String ?? args["name"] as? String ?? args["value"] as? String ?? L10n.text("詳細")
        fields = ["description", "text", "category", "location", "address"].compactMap { key in
            guard let value = args[key] as? String, !value.isEmpty else { return nil }
            return (L10n.text(key), value)
        }
        url = (args["url"] as? String).flatMap(GenUIHostPolicy.externalURL)
    }
}

struct GenUIEntityDetailView: View {
    let detail: GenUIEntityDetail
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(detail.title).font(.title2.bold())
                    ForEach(detail.fields, id: \.0) { key, value in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key).font(.caption).foregroundStyle(.secondary)
                            Text(value).textSelection(.enabled)
                        }
                    }
                    if let url = detail.url { Link(L10n.text("リンクを開く"), destination: url) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("閉じる")) { dismiss() } } }
            .toolbar(.visible, for: .navigationBar)
        }
    }
}

enum GenUIHostPolicy {
    static func externalURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    static func mapFrame(from object: Any?) -> CGRect? {
        guard let values = object as? [String: Any] else { return nil }
        let numbers = ["x", "y", "width", "height"].compactMap { values[$0] as? NSNumber }.map(\.doubleValue)
        guard numbers.count == 4, numbers.allSatisfy({ $0.isFinite && abs($0) <= 1_000_000 }),
              (0...10_000).contains(numbers[2]), (0...900).contains(numbers[3]) else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    static func snapshot(from object: Any) -> [String: JSONValue]? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object),
              let state = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return nil }
        return state
    }
}

/// Heavy WebKit instances are kept only for the two most recently detached
/// canvases. Older rows use a byte-budgeted still image while their DOM restores.
@MainActor
final class GenUIRenderCache: NSObject {
    static let shared = GenUIRenderCache()

    struct Preview {
        let image: UIImage
        let document: GenUIDocument
        let dark: Bool
        let width: CGFloat

        var byteCount: Int {
            guard let image = image.cgImage else { return 0 }
            return image.bytesPerRow * image.height
        }
    }

    private let rendererLimit: Int
    private let previewByteLimit: Int
    private var renderers: [(UUID, GenUIRichWebView.Coordinator)] = []
    private var previews: [(UUID, Preview)] = []
    private(set) var previewBytes = 0
    private var captureToken: UUID?
    private(set) var generation = 0
    var rendererCount: Int { renderers.count }

    init(rendererLimit: Int = 2, previewByteLimit: Int = 12 * 1024 * 1024) {
        self.rendererLimit = max(0, rendererLimit)
        self.previewByteLimit = max(0, previewByteLimit)
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(removeAll),
                                               name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func takeRenderer(for id: UUID) -> GenUIRichWebView.Coordinator? {
        guard let index = renderers.firstIndex(where: { $0.0 == id }) else { return nil }
        return renderers.remove(at: index).1
    }

    func retainRenderer(_ renderer: GenUIRichWebView.Coordinator, for id: UUID) {
        renderers.removeAll { $0.0 == id }
        renderers.append((id, renderer))
        while renderers.count > rendererLimit { renderers.removeFirst() }
    }

    func preview(for id: UUID) -> Preview? {
        guard let index = previews.firstIndex(where: { $0.0 == id }) else { return nil }
        let entry = previews.remove(at: index)
        previews.append(entry)
        return entry.1
    }

    func storePreview(_ preview: Preview, for id: UUID) {
        if let index = previews.firstIndex(where: { $0.0 == id }) {
            previewBytes -= previews.remove(at: index).1.byteCount
        }
        let cost = preview.byteCount
        guard cost > 0, cost <= previewByteLimit else { return }
        while previewBytes + cost > previewByteLimit || previews.count >= 24 {
            previewBytes -= previews.removeFirst().1.byteCount
        }
        previews.append((id, preview))
        previewBytes += cost
    }

    func beginPreviewCapture() -> UUID? {
        guard captureToken == nil else { return nil }
        let token = UUID()
        captureToken = token
        return token
    }

    @discardableResult
    func endPreviewCapture(_ token: UUID) -> Bool {
        guard captureToken == token else { return false }
        captureToken = nil
        return true
    }

    @objc func removeAll() {
        generation += 1
        renderers.removeAll()
        previews.removeAll()
        previewBytes = 0
    }
}

final class GenUIRichCanvas: UIView {
    let webView: WKWebView
    private let preview = UIImageView()
    private var previewRevision = 0
    var onLayout: (() -> Void)?

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        addSubview(webView)
        preview.contentMode = .scaleToFill
        preview.isUserInteractionEnabled = false
        preview.isAccessibilityElement = false
        addSubview(preview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        webView.frame = bounds
        preview.frame = bounds
        onLayout?()
    }

    var isShowingPreview: Bool { !preview.isHidden }

    func showPreview(_ image: UIImage?) {
        previewRevision += 1
        preview.layer.removeAllAnimations()
        preview.image = image
        preview.alpha = 1
        preview.isHidden = image == nil
    }

    func revealContent() {
        guard !preview.isHidden else { return }
        let revision = previewRevision
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.12, animations: {
            self.preview.alpha = 0
        }, completion: { _ in
            guard self.previewRevision == revision else { return }
            self.preview.image = nil
            self.preview.isHidden = true
        })
    }
}

struct GenUIRichWebView: UIViewRepresentable {
    let document: GenUIDocument
    let state: GenUIState
    let dark: Bool
    @Binding var height: CGFloat
    let onStatus: (String?) -> Void
    let onAction: ([String: Any]) -> Void

    func makeCoordinator() -> Coordinator {
        let cached = GenUIRenderCache.shared.takeRenderer(for: state.renderCacheID)
        let coordinator = state.richRenderer ?? cached ?? Coordinator(parent: self)
        state.richRenderer = coordinator
        coordinator.parent = self
        return coordinator
    }

    func makeUIView(context: Context) -> GenUIRichCanvas {
        context.coordinator.makeCanvas()
    }

    func updateUIView(_ canvas: GenUIRichCanvas, context: Context) {
        context.coordinator.parent = self
        context.coordinator.load(in: canvas.webView)
        canvas.webView.scrollView.isScrollEnabled = false
    }

    static func dismantleUIView(_ canvas: GenUIRichCanvas, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        // Release the SwiftUI host and its action closures while offscreen. The
        // cache must never retain the host's action closures or conversation.
        var parent: GenUIRichWebView?
        private(set) var webView: WKWebView?
        private weak var state: GenUIState?
        private weak var canvas: GenUIRichCanvas?
        private var previewTask: DispatchWorkItem?
        private var isRestoring = false
        private var previewCaptureInFlight = false
        private var loadedDocument: GenUIDocument?
        private var ready = false
        private var lastTheme: Bool?
        private var lastPhysicalTouch = Date.distantPast
        private var actionConsumed = true
        private var mapHosts: [String: MapHost] = [:]
        private var videoHosts: [String: GenUIYouTubePlayer] = [:]

        private struct MapHost {
            let props: [String: JSONValue]
            let controller: UIHostingController<AnyView>
            let container: UIView

            func remove() {
                controller.willMove(toParent: nil)
                controller.view.removeFromSuperview()
                controller.removeFromParent()
                container.removeFromSuperview()
            }
        }

        init(parent: GenUIRichWebView) {
            self.parent = parent
            state = parent.state
        }

        deinit {
            // Embedded players have their own WebKit message handlers.
            videoHosts.values.forEach { $0.remove() }
        }

        // WKUserContentController retains message handlers. Forward weakly so
        // the retained WebView and coordinator can both die with the row.
        private final class MessageHandler: NSObject, WKScriptMessageHandler {
            weak var target: Coordinator?

            init(target: Coordinator) { self.target = target }

            func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
                target?.userContentController(controller, didReceive: message)
            }
        }

        func makeCanvas() -> GenUIRichCanvas {
            let canvas = GenUIRichCanvas(webView: makeWebView())
            canvas.showPreview(nil)
            self.canvas = canvas
            canvas.onLayout = { [weak self] in
                self?.restorePreviewIfNeeded()
                if self?.ready == true && self?.isRestoring == true { self?.schedulePreviewCapture() }
            }
            return canvas
        }

        private func restorePreviewIfNeeded() {
            guard isRestoring, let canvas else { return }
            guard let state, let parent,
                  let preview = GenUIRenderCache.shared.preview(for: state.renderCacheID),
                  preview.document == parent.document, preview.dark == parent.dark,
                  abs(preview.width - canvas.bounds.width) < 1 else {
                canvas.showPreview(nil)
                return
            }
            canvas.showPreview(preview.image)
        }

        // Debounce interactive changes; never snapshot on each scroll/slider frame.
        private func schedulePreviewCapture() {
            previewTask?.cancel()
            guard parent != nil else { return }
            let task = DispatchWorkItem { [weak self] in self?.capturePreview() }
            previewTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
        }

        private func capturePreview() {
            guard !previewCaptureInFlight, let webView, let parent, let state, ready,
                  webView.bounds.width > 0, webView.bounds.height > 0 else { return }
            let cache = GenUIRenderCache.shared
            guard let token = cache.beginPreviewCapture() else { schedulePreviewCapture(); return }
            previewCaptureInFlight = true
            let generation = cache.generation
            let document = parent.document
            let dark = parent.dark
            let id = state.renderCacheID
            let width = webView.bounds.width
            let configuration = WKSnapshotConfiguration()
            configuration.rect = webView.bounds
            // Keep raster work bounded even for a very tall generated document.
            let scale = webView.traitCollection.displayScale
            configuration.snapshotWidth = NSNumber(value: Double(min(width * scale, sqrt(600_000 * width / webView.bounds.height)) / max(scale, 1)))
            // WebKit can suspend a snapshot when a canvas leaves its window.
            // Do not let that hold up other rows or leave a stale image covering UI.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard cache.endPreviewCapture(token), let self, self.loadedDocument == document else { return }
                self.isRestoring = false
                self.canvas?.revealContent()
            }
            webView.takeSnapshot(with: configuration) { [weak self] image, _ in
                self?.previewCaptureInFlight = false
                guard cache.endPreviewCapture(token), let self, self.loadedDocument == document else { return }
                if let image, generation == cache.generation {
                    cache.storePreview(.init(image: image, document: document, dark: dark, width: width), for: id)
                }
                self.isRestoring = false
                self.canvas?.revealContent()
            }
        }

        func makeWebView() -> WKWebView {
            if let webView { return webView }
            let configuration = YamabikoWebKitSupport.makeConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let handler = MessageHandler(target: self)
            configuration.userContentController.add(handler, name: "genui")
            let gestureWorld = WKContentWorld.world(name: "GenUIHostGestures")
            configuration.userContentController.add(handler, contentWorld: gestureWorld, name: "genuiGesture")
            configuration.userContentController.addUserScript(WKUserScript(source: """
                ['click','change','input','submit','keydown'].forEach(type => document.addEventListener(type, event => {
                    if (event.isTrusted) window.webkit.messageHandlers.genuiGesture.postMessage('trusted');
                }, true));
                """, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: gestureWorld))
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.accessibilityIdentifier = "genui-rich-canvas"
            webView.isOpaque = false
            webView.backgroundColor = .clear
            webView.scrollView.backgroundColor = .clear
            webView.scrollView.isScrollEnabled = false
            webView.scrollView.bounces = false
            webView.scrollView.keyboardDismissMode = .interactive
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            webView.navigationDelegate = self
            webView.uiDelegate = self
            self.webView = webView
            return webView
        }

        func detach() {
            previewTask?.cancel()
            canvas?.onLayout = nil
            canvas?.showPreview(nil)
            canvas = nil
            parent = nil
            lastPhysicalTouch = .distantPast
            actionConsumed = true
            webView?.endEditing(true)
            for player in videoHosts.values {
                player.webView.evaluateJavaScript("if (typeof player !== 'undefined') player?.pauseVideo?.();", completionHandler: nil)
            }
            // Preserve native map views too, but release the old cell controller.
            for host in mapHosts.values {
                host.controller.willMove(toParent: nil)
                host.controller.removeFromParent()
            }
            if let state { GenUIRenderCache.shared.retainRenderer(self, for: state.renderCacheID) }
        }

        private func attachMapControllers(in webView: WKWebView) {
            var responder: UIResponder? = webView
            while let current = responder, !(current is UIViewController) { responder = current.next }
            guard let controller = responder as? UIViewController else { return }
            for host in mapHosts.values where host.controller.parent == nil {
                controller.addChild(host.controller)
                host.controller.didMove(toParent: controller)
            }
        }

        func removeMaps() {
            mapHosts.values.forEach { $0.remove() }
            mapHosts.removeAll()
            videoHosts.values.forEach { $0.remove() }
            videoHosts.removeAll()
        }

        private func updateMaps(_ maps: [[String: Any]], in webView: WKWebView) {
            var retained = Set<String>()
            for map in maps {
                guard let id = map["id"] as? String, !id.isEmpty,
                      let props = map["props"].flatMap(GenUIHostPolicy.snapshot),
                      let frame = GenUIHostPolicy.mapFrame(from: map["frame"]),
                      let clip = GenUIHostPolicy.mapFrame(from: map["clip"]), retained.insert(id).inserted else { continue }
                if mapHosts[id]?.props != props {
                    mapHosts.removeValue(forKey: id)?.remove()
                    let content: AnyView
                    if let configuration = GenUIMapConfiguration(props: props) {
                        content = AnyView(GenUIInlineMapView(configuration: configuration))
                    } else {
                        let reason = L10n.text("地図には場所名・住所、または有効な緯度・経度を指定してください")
                        content = AnyView(Text(reason).font(.caption).padding().foregroundStyle(.secondary))
                        DiagnosticsLogger.log("GenUI inline map configuration rejected", level: .error, category: .app)
                    }
                    let controller = UIHostingController(rootView: content)
                    controller.safeAreaRegions = []
                    controller.view.backgroundColor = .clear
                    let container = UIView()
                    container.clipsToBounds = true
                    var responder: UIResponder? = webView
                    while let current = responder, !(current is UIViewController) { responder = current.next }
                    let parentController = responder as? UIViewController
                    parentController?.addChild(controller)
                    container.addSubview(controller.view)
                    webView.scrollView.addSubview(container)
                    if parentController != nil { controller.didMove(toParent: parentController) }
                    mapHosts[id] = MapHost(props: props, controller: controller, container: container)
                }
                guard let host = mapHosts[id] else { continue }
                host.controller.overrideUserInterfaceStyle = (parent?.dark ?? lastTheme ?? false) ? .dark : .light
                let visible = frame.intersection(clip)
                host.container.isHidden = visible.isNull || visible.isEmpty
                if !host.container.isHidden {
                    host.container.frame = visible
                    host.controller.view.frame = CGRect(x: frame.minX - visible.minX, y: frame.minY - visible.minY,
                                                        width: frame.width, height: frame.height)
                }
            }
            for id in Set(mapHosts.keys).subtracting(retained) { mapHosts.removeValue(forKey: id)?.remove() }
            attachMapControllers(in: webView)
        }

        private func updateVideos(_ videos: [[String: Any]], in webView: WKWebView) {
            var retained = Set<String>()
            for video in videos {
                guard let id = video["id"] as? String, let videoID = video["videoId"] as? String,
                      videoID.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil,
                      let frame = GenUIHostPolicy.mapFrame(from: video["frame"]), retained.insert(id).inserted else { continue }
                if videoHosts[id] == nil {
                    let player = GenUIYouTubePlayer(videoID: videoID, title: video["title"] as? String ?? "YouTube", poster: video["poster"] as? Bool ?? false)
                    player.onEvent = { [weak webView] type, value in
                        webView?.callAsyncJavaScript("window.GenUIRuntime.videoEvent(id,type,value);", arguments: ["id": id, "type": type, "value": value as Any? ?? NSNull()], in: nil, in: .page, completionHandler: nil)
                    }
                    videoHosts[id] = player
                    webView.scrollView.addSubview(player.webView)
                }
                videoHosts[id]?.webView.frame = frame
            }
            for id in Array(videoHosts.keys) where !retained.contains(id) { videoHosts.removeValue(forKey: id)?.remove() }
        }

        func load(in webView: WKWebView) {
            guard let parent else { return }
            attachMapControllers(in: webView)
            guard loadedDocument != parent.document else {
                if ready && isRestoring { schedulePreviewCapture() }
                if lastTheme != parent.dark {
                    lastTheme = parent.dark
                    webView.evaluateJavaScript("window.GenUIRuntime?.setTheme('\(parent.dark ? "dark" : "light")')", completionHandler: nil)
                }
                return
            }
            if let loadedDocument, loadedDocument.isRich, parent.document.isRich {
                guard ready else { return }
                let encoder = JSONEncoder()
                if let previous = try? encoder.encode(loadedDocument), let next = try? encoder.encode(parent.document),
                   Self.mediaOrigins(previous) == Self.mediaOrigins(next) {
                    self.loadedDocument = parent.document
                    webView.callAsyncJavaScript("const value=JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(encoded),c=>c.charCodeAt(0)))); window.GenUIRuntime.updateDocument(value);window.__GENUI_SET_THEME__(theme);", arguments: ["encoded": next.base64EncodedString(), "theme": parent.dark ? "dark" : "light"], in: nil, in: .page, completionHandler: { result in
                        if case .failure(let error) = result { DiagnosticsLogger.log("GenUI document update failed", category: .app, error: error) }
                    })
                    return
                }
            }
            ready = false
            isRestoring = true
            restorePreviewIfNeeded()
            guard let html = Self.html(document: parent.document, snapshot: parent.state.richSnapshot, dark: parent.dark) else {
                DispatchQueue.main.async { [weak self] in self?.parent?.onStatus(L10n.text("GenUIの表示リソースを読み込めません")) }
                return
            }
            removeMaps()
            loadedDocument = parent.document
            lastTheme = parent.dark
            let mathDirectory = MathMarkdownResourceResolver.mathJaxScriptURL(in: .main)?.deletingLastPathComponent()
            webView.loadHTMLString(html, baseURL: mathDirectory)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "genuiGesture", message.frameInfo.isMainFrame {
                // This handler exists only in an isolated content world. Generated
                // page code cannot forge it; trusted keyboard/VoiceOver events work.
                lastPhysicalTouch = Date()
                actionConsumed = false
                return
            }
            guard message.frameInfo.isMainFrame, let object = message.body as? [String: Any], let type = object["type"] as? String else { return }
            switch type {
            case "height":
                ready = true
                if let parent, loadedDocument != parent.document, let webView = message.webView { load(in: webView) }
                guard let number = object["height"] as? NSNumber, number.doubleValue.isFinite else { return }
                // The conversation owns vertical scrolling. Fit the complete document
                // so diagrams and controls stay in the same reading flow.
                let height = max(CGFloat(number.doubleValue), 60)
                DispatchQueue.main.async { [weak self, weak webView = message.webView] in
                    guard let state = self?.state else { return }
                    if abs(state.richHeight - height) > 1 { state.richHeight = height }
                    webView?.scrollView.isScrollEnabled = false
                    self?.schedulePreviewCapture()
                }
            case "videos":
                guard let videos = object["videos"] as? [[String: Any]] else { return }
                DispatchQueue.main.async { [weak self, weak webView = message.webView] in
                    guard let self, let webView else { return }
                    self.updateVideos(videos, in: webView)
                }
            case "unsupported":
                let reason = object["reason"] as? String ?? "reference-server-required"
                DiagnosticsLogger.log("GenUI reference operation unavailable", category: .app, metadata: ["reason": reason])
                DispatchQueue.main.async { [weak self] in
                    let label = reason.hasPrefix("reference-server-required:")
                        ? L10n.text("参考元のサービスが必要な操作です")
                        : L10n.text("このクライアント操作は未対応です")
                    self?.parent?.onStatus(label + " (" + reason + ")")
                }
            case "maps":
                guard let maps = object["maps"] as? [[String: Any]] else { return }
                DispatchQueue.main.async { [weak self, weak webView = message.webView] in
                    guard let self, let webView else { return }
                    self.updateMaps(maps, in: webView)
                }
            case "state":
                guard let state = object["state"].flatMap(GenUIHostPolicy.snapshot) else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.state?.richSnapshot = state
                    self?.schedulePreviewCapture()
                }
            case "warning":
                let reason = String((object["message"] as? String ?? "GenUI section failed").prefix(500))
                DiagnosticsLogger.log("GenUI section rendering failed", category: .app,
                                      metadata: ["reason": reason, "path": object["path"] as? String ?? "unknown"])
            case "error":
                let text = String((object["message"] as? String ?? "GenUI rendering failed").prefix(500))
                DiagnosticsLogger.log("GenUI rendering failed", category: .app, metadata: ["reason": text])
                DispatchQueue.main.async { [weak self] in self?.parent?.onStatus(text) }
            case "referenceEvent":
                DiagnosticsLogger.log("GenUI reference event", category: .app, metadata: ["event": String(describing: object["event"] ?? "")])
            default:
                // JS cannot initiate native side effects on load or from timers.
                guard !actionConsumed, Date().timeIntervalSince(lastPhysicalTouch) < 1.5 else {
                    DiagnosticsLogger.log("GenUI host action rejected without a trusted interaction", category: .app, metadata: ["type": type])
                    return
                }
                actionConsumed = true
                DispatchQueue.main.async { [weak self] in self?.parent?.onAction(object) }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            if navigationAction.targetFrame?.isMainFrame == false,
               url?.scheme == "https", url?.host == "www.youtube-nocookie.com" {
                decisionHandler(.allow)
            } else if navigationAction.navigationType == .other, url?.scheme == "about" || url?.isFileURL == true {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            guard frame.isMainFrame, (prompt.hasPrefix("__genuiCEL:") || prompt.hasPrefix("__genuiChart:")) else { completionHandler(nil); return }
            let prefix = prompt.hasPrefix("__genuiChart:") ? "__genuiChart:" : "__genuiCEL:"
            let result = GenUICELRuntime.evaluate(String(prompt.dropFirst(prefix.count)))
            completionHandler(result)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            // A suspended WebKit process may be reclaimed while offscreen.
            // Reload through the same renderer on its next attachment.
            loadedDocument = nil
            ready = false
            if parent != nil { load(in: webView) }
            DiagnosticsLogger.log("GenUI WebKit process terminated", category: .app)
        }

        static func html(document: GenUIDocument, snapshot: [String: JSONValue]?, dark: Bool) -> String? {
            func asset(_ name: String, extension ext: String) -> String? {
                let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "genui")
                    ?? Bundle.main.url(forResource: name, withExtension: ext)
                return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            }
            guard let runtime = asset("runtime", extension: "js"), let css = asset("styles", extension: "css"),
                  let encoded = try? JSONEncoder().encode(document) else { return nil }
            guard let components = asset("reference-components", extension: "js"),
                  let tokens = asset("reference-tokens", extension: "js"),
                  let icons = asset("reference-icons", extension: "js"),
                  let lottie = asset("lottie-light", extension: "js"),
                  let markdown = asset("markdown-it", extension: "js") else { return nil }
            let snapshot64 = (try? JSONEncoder().encode(snapshot ?? [:]).base64EncodedString()) ?? "e30="
            let origins = mediaOrigins(encoded)
            let policy = "default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' file:; style-src 'unsafe-inline'; img-src data: \(origins); media-src \(origins.isEmpty ? "'none'" : origins); font-src file: data:; connect-src \(origins.isEmpty ? "'none'" : origins); frame-src https://www.youtube-nocookie.com; base-uri 'none'; form-action 'none'"
            let math = MathMarkdownResourceResolver.mathJaxScriptURL(in: .main).map {
                "<script>window.MathJax={startup:{typeset:false},tex:{inlineMath:[['$','$'],['\\\\(','\\\\)']]}};</script><script src=\"\($0.lastPathComponent)\"></script>"
            } ?? ""
            return """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"><meta http-equiv="Content-Security-Policy" content="\(policy)"><style>\(css)</style>\(math)</head><body><div id="root"></div><script>
            const decode=b=>JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b),c=>c.charCodeAt(0))));
            window.__GENUI_DOCUMENT__=decode('\(encoded.base64EncodedString())');
            window.__GENUI_SAVED_STATE__=decode('\(snapshot64)');
            window.__GENUI_IS_MOBILE__=true;
            window.__GENUI_THEME__='\(dark ? "dark" : "light")';
            window.__GENUI_LOCALE__='\(Locale.current.language.languageCode?.identifier ?? "en")';
            \(markdown)
            \(lottie)
            \(components)
            \(tokens)
            \(icons)
            \(runtime)
            </script></body></html>
            """
        }

        private static func mediaOrigins(_ data: Data) -> String {
            var origins = Set<String>()
            func scan(_ object: Any) {
                if let dictionary = object as? [String: Any] {
                    // Client code must declare media URLs in resources or node props.
                    for (key, value) in dictionary where key != "code" { scan(value) }
                } else if let array = object as? [Any] {
                    array.forEach(scan)
                } else if let raw = object as? String, let url = GenUIHostPolicy.externalURL(raw), let host = url.host {
                    origins.insert("https://\(host)\(url.port.map { ":\($0)" } ?? "")")
                }
            }
            if let object = try? JSONSerialization.jsonObject(with: data) { scan(object) }
            return origins.sorted().joined(separator: " ")
        }
    }
}
