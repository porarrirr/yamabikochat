import SwiftUI
import WebKit

private struct GenUINewTurnKey: EnvironmentKey {
    static let defaultValue: (String) -> Bool = { _ in false }
}

private struct GenUIRouteKey: EnvironmentKey {
    static let defaultValue: (ChatWorkspaceRoute) -> Void = { _ in }
}

extension EnvironmentValues {
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
    @Environment(\.onGenUINewTurn) private var issueNewTurn
    @Environment(\.openURL) private var openURL
    @State private var height: CGFloat = 240
    @State private var status: String?
    @Environment(\.onGenUIRoute) private var presentRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GenUIRichWebView(document: document, state: state, dark: colorScheme == .dark, height: $height, onStatus: { status = $0 }, onAction: handle)
                .frame(height: height)
                .accessibilityIdentifier("genui-rich-canvas")
            // Reserve feedback space so status updates preserve the hosted canvas bounds.
            Text(status ?? " ").font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                .padding(.horizontal, 16)
                .opacity(status == nil ? 0 : 1)
                .accessibilityHidden(status == nil)
                .accessibilityIdentifier("genui-rich-status")
        }
        .background(Color.teal.opacity(0.04), in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(Color.teal.opacity(0.18)) }
        .clipShape(RoundedRectangle(cornerRadius: 22))
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
        case "issueNewTurn":
            guard let query = object["query"] as? String, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, query.utf8.count <= 16_384 else { return }
            status = issueNewTurn(query) ? nil : L10n.text("送信中の応答や入力欄の下書きを確認してください")
        case "openEntityDetail":
            presentRoute(.genUIEntity(GenUIEntityDetail(object["args"] as? [String: Any] ?? [:])))
        case "openMap":
            guard let props = object["props"] as? [String: Any],
                  let data = try? JSONSerialization.data(withJSONObject: props),
                  let decoded = try? JSONDecoder().decode([String: JSONValue].self, from: data),
                  let configuration = GenUIMapConfiguration(props: decoded) else {
                status = L10n.text("地図には有効な緯度・経度が必要です")
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
        fields = ["description", "category", "location", "address"].compactMap { key in
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

    static func snapshot(from object: Any) -> [String: JSONValue]? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object), data.count <= 131_072,
              let state = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return nil }
        return state
    }
}

struct GenUIRichWebView: UIViewRepresentable {
    let document: GenUIDocument
    let state: GenUIState
    let dark: Bool
    @Binding var height: CGFloat
    let onStatus: (String?) -> Void
    let onAction: ([String: Any]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = YamabikoWebKitSupport.makeConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "genui")
        let gestureWorld = WKContentWorld.world(name: "GenUIHostGestures")
        configuration.userContentController.add(context.coordinator, contentWorld: gestureWorld, name: "genuiGesture")
        configuration.userContentController.addUserScript(WKUserScript(source: """
            ['click','change','input','submit','keydown'].forEach(type => document.addEventListener(type, event => {
                if (event.isTrusted) window.webkit.messageHandlers.genuiGesture.postMessage('trusted');
            }, true));
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: gestureWorld))
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = true
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.load(in: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "genui")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "genuiGesture", contentWorld: .world(name: "GenUIHostGestures"))
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: GenUIRichWebView
        private var loadedDocument: GenUIDocument?
        private var lastTheme: Bool?
        private var lastPhysicalTouch = Date.distantPast
        private var actionConsumed = true

        init(parent: GenUIRichWebView) { self.parent = parent }

        func load(in webView: WKWebView) {
            guard loadedDocument != parent.document else {
                if lastTheme != parent.dark {
                    lastTheme = parent.dark
                    webView.evaluateJavaScript("window.GenUIRuntime?.setTheme('\(parent.dark ? "dark" : "light")')", completionHandler: nil)
                }
                return
            }
            guard let html = Self.html(document: parent.document, snapshot: parent.state.richSnapshot, dark: parent.dark) else {
                DispatchQueue.main.async { [weak self] in self?.parent.onStatus(L10n.text("GenUIの表示リソースを読み込めません")) }
                return
            }
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
                guard let number = object["height"] as? NSNumber, number.doubleValue.isFinite else { return }
                // Keep long web UIs in a usable viewport. WebKit owns scrolling
                // inside the canvas, preserving native input gesture handling.
                let height = CGFloat(min(max(number.doubleValue, 60), 560))
                DispatchQueue.main.async { [weak self, weak webView = message.webView] in
                    guard let self else { return }
                    if abs(self.parent.height - height) > 1 { self.parent.height = height }
                    webView?.scrollView.isScrollEnabled = number.doubleValue > 560
                }
            case "state":
                guard let state = object["state"].flatMap(GenUIHostPolicy.snapshot) else { return }
                DispatchQueue.main.async { [weak self] in self?.parent.state.richSnapshot = state }
            case "error":
                let text = String((object["message"] as? String ?? "GenUI rendering failed").prefix(500))
                DiagnosticsLogger.log("GenUI rendering failed", category: .app, metadata: ["reason": text])
                DispatchQueue.main.async { [weak self] in self?.parent.onStatus(text) }
            default:
                // JS cannot initiate native side effects on load or from timers.
                guard !actionConsumed, Date().timeIntervalSince(lastPhysicalTouch) < 1.5 else {
                    DiagnosticsLogger.log("GenUI host action rejected without a trusted interaction", category: .app, metadata: ["type": type])
                    return
                }
                actionConsumed = true
                DispatchQueue.main.async { [weak self] in self?.parent.onAction(object) }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            if navigationAction.navigationType == .other, url?.scheme == "about" || url?.isFileURL == true {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            parent.onStatus(L10n.text("GenUIの表示処理が停止しました。会話を開き直してください"))
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
            let snapshot64 = (try? JSONEncoder().encode(snapshot ?? [:]).base64EncodedString()) ?? "e30="
            let origins = mediaOrigins(encoded)
            let policy = "default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' file:; style-src 'unsafe-inline'; img-src data: \(origins); media-src \(origins.isEmpty ? "'none'" : origins); font-src file: data:; connect-src 'none'; frame-src 'none'; base-uri 'none'; form-action 'none'"
            let math = MathMarkdownResourceResolver.mathJaxScriptURL(in: .main).map {
                "<script>window.MathJax={startup:{typeset:false}};</script><script src=\"\($0.lastPathComponent)\"></script>"
            } ?? ""
            return """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1"><meta http-equiv="Content-Security-Policy" content="\(policy)"><style>\(css)</style>\(math)</head><body><div id="root"></div><script>
            const decode=b=>JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b),c=>c.charCodeAt(0))));
            window.__GENUI_DOCUMENT__=decode('\(encoded.base64EncodedString())');
            window.__GENUI_SAVED_STATE__=decode('\(snapshot64)');
            window.__GENUI_THEME__='\(dark ? "dark" : "light")';
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
