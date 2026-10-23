import CryptoKit
import Foundation
import WebKit
#if canImport(UIKit)
import UIKit
#endif

/// The WebContent process receives only immutable runtime assets and workspace
/// copies. It has no file URL grant, Keychain entitlement, network access, or RPC
/// that could ask the app to read a path or execute a native operation.
@MainActor
final class PythonWebSandbox: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView?
    private var startup: CheckedContinuation<Void, Error>?
    private var execution: CheckedContinuation<PythonSandboxResult, Error>?
    private var executionID: String?
    private var timeoutTask: Task<Void, Never>?
    private var initializationTask: Task<Void, Never>?
    private var allowsInitialNavigation = false

    static let contentSecurityPolicy = "default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval' blob:; worker-src blob:; connect-src 'none'; img-src 'none'; style-src 'none'; font-src 'none'; media-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"

    func start() async throws {
        try Task.checkCancellation()
        if webView != nil, startup == nil { return }
        guard startup == nil else { throw PythonToolError.invalidResponse }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                startup = continuation
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(90))
                    guard !Task.isCancelled else { return }
                    self?.dispose(error: PythonToolError.runtimeResourcesMissing)
                }
                initializationTask = Task { [weak self] in
                    do { try await self?.configure() }
                    catch { self?.dispose(error: error) }
                }
            }
        } onCancel: {
            Task { @MainActor in self.dispose(error: CancellationError()) }
        }
    }

    private func configure() async throws {
        let content = WKUserContentController()
        content.add(self, name: "pythonResult")
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController = content
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        // CSP also applies to Workers, including Python's JS escape hatches.
        let rules = """
        [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},
         {"trigger":{"url-filter":"^wss?://"},"action":{"type":"block"}},
         {"trigger":{"url-filter":"^file://"},"action":{"type":"block"}},
         {"trigger":{"url-filter":"^ftp://"},"action":{"type":"block"}}]
        """
        DiagnosticsLogger.log("Python sandbox preparing browser policy", category: .network, metadata: ["stage": "policy"])
        let ruleList = try await WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "YamabikoPythonNoNetworkV1", encodedContentRuleList: rules
        )
        try Task.checkCancellation()
        guard startup != nil else { throw CancellationError() }
        if let ruleList { content.add(ruleList) }
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        view.navigationDelegate = self
        webView = view
        #if canImport(UIKit)
        // WebKit may suspend Workers in a detached page. Keep the noninteractive
        // runtime attached behind the app's content while it is in the foreground.
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        view.alpha = 0.01
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.insertSubview(view, at: 0)
        #endif
        DiagnosticsLogger.log("Python sandbox loading isolated page", category: .network, metadata: ["stage": "page"])
        let script = try resource("python-sandbox", extension: "js")
        let html = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(Self.contentSecurityPolicy)\"><script>\(script)</script>"
        allowsInitialNavigation = true
        view.loadHTMLString(html, baseURL: nil)
    }

    func execute(code: String, reset: Bool, files: [PythonSandboxFile], timeout: TimeInterval) async throws -> PythonSandboxResult {
        try await start()
        try Task.checkCancellation()
        guard execution == nil, let view = webView else { throw PythonToolError.invalidResponse }
        let id = UUID().uuidString
        let encoded = try JSONEncoder().encode(files)
        let fileObjects = try JSONSerialization.jsonObject(with: encoded)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                execution = continuation
                executionID = id
                timeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(timeout))
                    guard !Task.isCancelled else { return }
                    self?.dispose(error: PythonSandboxTimeout())
                }
                Task { [weak self] in
                    do {
                        _ = try await view.callAsyncJavaScript(
                            "pythonSandbox.execute(id, {code, reset, files});",
                            arguments: ["id": id, "code": code, "reset": reset, "files": fileObjects],
                            in: nil, contentWorld: .page
                        )
                    } catch { self?.dispose(error: error) }
                }
            }
        } onCancel: {
            Task { @MainActor in self.dispose(error: CancellationError()) }
        }
    }

    func dispose(error: Error = CancellationError()) {
        timeoutTask?.cancel()
        timeoutTask = nil
        initializationTask?.cancel()
        initializationTask = nil
        // Terminating the Worker stops even a Python/C infinite loop. Releasing
        // the WebView also discards the entire ephemeral content environment.
        webView?.evaluateJavaScript("pythonSandbox.dispose()", completionHandler: nil)
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "pythonResult")
        webView?.navigationDelegate = nil
        webView?.removeFromSuperview()
        webView = nil
        let pendingStartup = startup
        let pendingExecution = execution
        startup = nil
        execution = nil
        executionID = nil
        pendingStartup?.resume(throwing: error)
        pendingExecution?.resume(throwing: error)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard startup != nil else { return }
        DiagnosticsLogger.log("Python sandbox loading offline assets", category: .network, metadata: ["stage": "assets"])
        Task {
            do {
                guard let root = Bundle.main.url(forResource: "Pyodide", withExtension: nil) else { throw PythonToolError.runtimeResourcesMissing }
                let manifest = try JSONDecoder().decode(PythonAssetManifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
                for (name, expectedHash) in manifest.files.sorted(by: { $0.key < $1.key }) {
                    guard !name.contains("/"), !name.contains("..") else { throw PythonToolError.runtimeResourcesMissing }
                    let data = try Data(contentsOf: root.appendingPathComponent(name))
                    guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expectedHash else { throw PythonToolError.runtimeResourcesMissing }
                    try await addAsset(name: name, data: data)
                }
                try await addAsset(name: "yamabiko_runtime.py", data: Data(resource("yamabiko_runtime", extension: "py").utf8))
                if let fonts = Bundle.main.url(forResource: "Fonts", withExtension: nil) {
                    for font in try FileManager.default.contentsOfDirectory(at: fonts, includingPropertiesForKeys: nil) where font.pathExtension == "ttf" {
                        try await addAsset(name: "Fonts/" + font.lastPathComponent, data: Data(contentsOf: font))
                    }
                }
                let worker = try resource("python-worker", extension: "js")
                DiagnosticsLogger.log("Python sandbox starting WebAssembly worker", category: .network, metadata: ["stage": "worker"])
                _ = try await webView.callAsyncJavaScript("pythonSandbox.start(source)", arguments: ["source": worker], in: nil, contentWorld: .page)
            } catch { dispose(error: error) }
        }
    }

    private func addAsset(name: String, data: Data) async throws {
        guard let webView, startup != nil else { throw CancellationError() }
        _ = try await webView.callAsyncJavaScript("pythonSandbox.addAsset(name, data)", arguments: ["name": name, "data": data.base64EncodedString()], in: nil, contentWorld: .page)
    }

    private func resource(_ name: String, extension fileExtension: String) throws -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: fileExtension) else { throw PythonToolError.runtimeResourcesMissing }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let object = message.body as? [String: Any], let type = object["type"] as? String else { return }
        if type == "ready", let continuation = startup {
            startup = nil
            timeoutTask?.cancel()
            timeoutTask = nil
            continuation.resume()
            return
        }
        if type == "startup_error" || type == "worker_error" {
            if startup != nil, let detail = object["message"] as? String {
                DiagnosticsLogger.log("WebAssembly Python initialization failed", category: .network, metadata: ["detail": String(detail.prefix(1024))])
            }
            dispose(error: PythonToolError.invalidResponse)
            return
        }
        guard let id = object["id"] as? String, id == executionID, let continuation = execution else { return }
        guard type == "result", let data = try? JSONSerialization.data(withJSONObject: object),
              let result = try? JSONDecoder().decode(PythonSandboxResult.self, from: data) else {
            dispose(error: PythonToolError.invalidResponse)
            return
        }
        execution = nil
        executionID = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(returning: result)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { dispose(error: PythonToolError.invalidResponse) }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme
        if allowsInitialNavigation && ["about", "applewebdata"].contains(scheme ?? "") {
            allowsInitialNavigation = false
            decisionHandler(.allow)
        } else { decisionHandler(.cancel) }
    }
}

private struct PythonAssetManifest: Decodable { var files: [String: String] }
struct PythonSandboxTimeout: Error {}
struct PythonSandboxResult: Decodable, Sendable {
    var result: PythonExecutionResponse
    var files: [PythonSandboxFile]
}
