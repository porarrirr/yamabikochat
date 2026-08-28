import Foundation
import SwiftUI
import UIKit
import WebKit

enum MermaidHTMLBuilder {
    static let maximumSourceLength = 50_000
    static let maximumEdgeCount = 500

    static func buildHTML(
        sourcePayload: String,
        colorScheme: ColorScheme,
        scriptFilename: String = "mermaid.min.js",
        allowsZoom: Bool
    ) -> String {
        let theme = colorScheme == .dark ? "dark" : "default"
        let background = colorScheme == .dark ? "#1C1C1E" : "#FFFFFF"
        let foreground = colorScheme == .dark ? "#F2F2F7" : "#1C1C1E"
        let viewport = allowsZoom
            ? "width=device-width, initial-scale=1, maximum-scale=5, user-scalable=yes"
            : "width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"
        let documentHeight = allowsZoom ? "height: 100%;" : ""
        let rootHeight = allowsZoom ? "height: 100%;" : "min-height: 44px;"
        let svgSizing = allowsZoom
            ? "width: auto; max-width: 100%; max-height: calc(100vh - 24px); height: auto;"
            : "width: 100%; max-width: 100%; height: auto;"

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="\(viewport)" />
          <meta name="color-scheme" content="light dark" />
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'self' 'unsafe-inline' file:; style-src 'unsafe-inline'; img-src data:; connect-src 'none'; media-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'" />
          <style>
            html, body {
              margin: 0;
              padding: 0;
              \(documentHeight)
              background: transparent;
              color: \(foreground);
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
            }
            body { background: \(background); }
            #yamabiko-mermaid-root {
              box-sizing: border-box;
              width: 100%;
              \(rootHeight)
              padding: 12px;
              display: flex;
              align-items: flex-start;
              justify-content: center;
            }
            #yamabiko-mermaid-root svg {
              display: block;
              \(svgSizing)
            }
            #yamabiko-mermaid-root a { pointer-events: none !important; }
          </style>
        </head>
        <body>
          <div id="yamabiko-mermaid-root" role="img" aria-label="Mermaid diagram"></div>
          <script src="\(scriptFilename)" onerror="window.__yamabikoMermaidFailure('Mermaid library could not be loaded.')"></script>
          <script>
            (function() {
              var source = \(sourcePayload);
              var root = document.getElementById('yamabiko-mermaid-root');
              var lastHeight = -1;

              function post(message) {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mermaidRenderState) {
                  window.webkit.messageHandlers.mermaidRenderState.postMessage(message);
                }
              }

              function reportHeight() {
                if (!root) return;
                var rect = root.getBoundingClientRect();
                var height = Math.ceil(Math.max(root.scrollHeight || 0, rect && isFinite(rect.height) ? rect.height : 0));
                if (!isFinite(height) || height <= 0 || height === lastHeight) return;
                lastHeight = height;
                post({ status: 'success', height: height });
              }

              window.__yamabikoMermaidFailure = function(message) {
                post({ status: 'error', message: String(message || 'Unknown Mermaid rendering error') });
              };

              async function render() {
                try {
                  if (typeof source !== 'string' || source.length === 0) {
                    throw new Error('Mermaid source is empty.');
                  }
                  if (source.length > \(maximumSourceLength)) {
                    throw new Error('Mermaid source exceeds the configured size limit.');
                  }
                  if (!window.mermaid || typeof window.mermaid.render !== 'function') {
                    throw new Error('Mermaid library is unavailable.');
                  }
                  window.mermaid.initialize({
                    startOnLoad: false,
                    securityLevel: 'strict',
                    htmlLabels: false,
                    flowchart: { htmlLabels: false },
                    theme: '\(theme)',
                    suppressErrorRendering: true,
                    maxTextSize: \(maximumSourceLength),
                    maxEdges: \(maximumEdgeCount),
                    secure: [
                      'securityLevel', 'startOnLoad', 'maxTextSize', 'maxEdges',
                      'htmlLabels', 'flowchart'
                    ]
                  });
                  var result = await window.mermaid.render('yamabiko-mermaid-svg', source);
                  root.innerHTML = result.svg;
                  root.querySelectorAll('a').forEach(function(link) {
                    link.removeAttribute('href');
                    link.removeAttribute('xlink:href');
                    link.style.pointerEvents = 'none';
                  });
                  var svg = root.querySelector('svg');
                  if (!svg) throw new Error('Mermaid did not produce an SVG document.');
                  svg.setAttribute('role', 'img');
                  svg.setAttribute('aria-label', 'Mermaid diagram');
                  svg.removeAttribute('height');
                  reportHeight();
                  requestAnimationFrame(reportHeight);
                  setTimeout(reportHeight, 80);
                  setTimeout(reportHeight, 240);
                  if (window.ResizeObserver) {
                    new ResizeObserver(reportHeight).observe(root);
                  }
                } catch (error) {
                  window.__yamabikoMermaidFailure(error && error.message ? error.message : error);
                }
              }

              window.addEventListener('load', render, { once: true });
            })();
          </script>
        </body>
        </html>
        """
    }
}

enum MermaidResourceResolver {
    static let version = "11.17.2"

    static func scriptURL(in bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "mermaid")
            ?? bundle.url(forResource: "mermaid.min", withExtension: "js")
    }
}

enum MermaidWebResourceLoader {
    static func preparedResourceDirectory(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let scriptURL = MermaidResourceResolver.scriptURL(in: bundle) else {
            throw MermaidRenderError.missingResource
        }
        guard let cacheRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw MermaidRenderError.unavailableCacheDirectory
        }

        let destinationDirectory = cacheRoot.appendingPathComponent(
            "yamabiko-mermaid-\(MermaidResourceResolver.version)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let destinationURL = destinationDirectory.appendingPathComponent("mermaid.min.js")
        if !fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.copyItem(at: scriptURL, to: destinationURL)
        }
        return destinationDirectory
    }
}

enum MermaidRenderError: LocalizedError {
    case missingResource
    case unavailableCacheDirectory
    case emptySource
    case sourceTooLarge(limit: Int)

    var errorDescription: String? {
        switch self {
        case .missingResource:
            return "Mermaidの描画ライブラリが見つかりません。"
        case .unavailableCacheDirectory:
            return "Mermaidの描画準備に必要な保存領域を使用できません。"
        case .emptySource:
            return "Mermaidのソースが空です。"
        case let .sourceTooLarge(limit):
            return "Mermaidのソースがサイズ上限（\(limit)文字）を超えています。"
        }
    }
}

enum MermaidNavigationPolicy {
    static func allowsInitialDocument(_ url: URL?, isMainFrame: Bool) -> Bool {
        guard isMainFrame, let scheme = url?.scheme?.lowercased() else { return false }
        return scheme == "file" || scheme == "about"
    }
}

struct MermaidDiagramView: View {
    let source: String
    var expanded = false
    var onExpand: (() -> Void)?
    var onLayoutChange: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var measuredHeight: CGFloat = 180
    @State private var renderError: String?

    private let inlineMaximumHeight: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !expanded {
                HStack(spacing: 12) {
                    Text("Mermaid")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = source
                    } label: {
                        Label(L10n.text("コピー"), systemImage: "doc.on.doc")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.plain)
                    if let onExpand, renderError == nil {
                        Button(action: onExpand) {
                            Label(L10n.text("拡大"), systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
                Divider()
            }

            if let renderError {
                VStack(alignment: .leading, spacing: 8) {
                    Label(L10n.text("Mermaidを描画できません"), systemImage: "exclamationmark.triangle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                    Text(renderError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            } else {
                ZStack(alignment: .bottom) {
                    MermaidWebView(
                        source: source,
                        colorScheme: colorScheme,
                        allowsInteraction: expanded,
                        measuredHeight: $measuredHeight,
                        renderError: $renderError,
                        onLayoutChange: onLayoutChange
                    )
                    .frame(height: expanded ? nil : min(measuredHeight, inlineMaximumHeight))
                    .frame(maxHeight: expanded ? .infinity : inlineMaximumHeight)

                    if !expanded, measuredHeight > inlineMaximumHeight {
                        LinearGradient(
                            colors: [.clear, Color(uiColor: .secondarySystemBackground)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 44)
                        .allowsHitTesting(false)
                    }

                    if !expanded, let onExpand {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onExpand)
                            .accessibilityLabel(Text(L10n.text("Mermaid図を拡大")))
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
        }
        .background(Color(uiColor: expanded ? .systemBackground : .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 0 : 12, style: .continuous))
    }
}

private struct MermaidWebView: UIViewRepresentable {
    let source: String
    let colorScheme: ColorScheme
    let allowsInteraction: Bool
    @Binding var measuredHeight: CGFloat
    @Binding var renderError: String?
    var onLayoutChange: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.messageName)
        let configuration = YamabikoWebKitSupport.makeConfiguration(userContentController: controller)
        configuration.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = allowsInteraction
        webView.scrollView.isScrollEnabled = allowsInteraction
        webView.scrollView.pinchGestureRecognizer?.isEnabled = allowsInteraction
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        webView.scrollView.bounces = allowsInteraction
        webView.scrollView.isScrollEnabled = allowsInteraction
        webView.scrollView.pinchGestureRecognizer?.isEnabled = allowsInteraction

        let signature = Coordinator.Signature(
            source: source,
            colorScheme: colorScheme,
            allowsInteraction: allowsInteraction
        )
        guard context.coordinator.beginUpdate(signature) else { return }

        do {
            guard !source.isEmpty else { throw MermaidRenderError.emptySource }
            guard source.count <= MermaidHTMLBuilder.maximumSourceLength else {
                throw MermaidRenderError.sourceTooLarge(limit: MermaidHTMLBuilder.maximumSourceLength)
            }
            let resourceDirectory = try MermaidWebResourceLoader.preparedResourceDirectory()
            let html = MermaidHTMLBuilder.buildHTML(
                sourcePayload: source.mermaidJSONStringLiteral,
                colorScheme: colorScheme,
                allowsZoom: allowsInteraction
            )
            renderError = nil
            webView.loadHTMLString(html, baseURL: resourceDirectory)
        } catch {
            context.coordinator.fail(error.localizedDescription)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.messageName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        struct Signature: Equatable {
            let source: String
            let colorScheme: ColorScheme
            let allowsInteraction: Bool
        }

        static let messageName = "mermaidRenderState"
        var parent: MermaidWebView
        private var signature: Signature?

        init(parent: MermaidWebView) {
            self.parent = parent
        }

        func beginUpdate(_ signature: Signature) -> Bool {
            guard self.signature != signature else { return false }
            self.signature = signature
            return true
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.messageName,
                  let body = message.body as? [String: Any],
                  let status = body["status"] as? String else { return }

            if status == "success", let height = body["height"] as? NSNumber {
                let value = max(44, CGFloat(truncating: height).rounded(.up))
                DispatchQueue.main.async {
                    guard abs(self.parent.measuredHeight - value) > 1 else { return }
                    self.parent.renderError = nil
                    self.parent.measuredHeight = value
                    self.parent.onLayoutChange?()
                }
            } else if status == "error" {
                fail((body["message"] as? String) ?? "Unknown Mermaid rendering error")
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let allowed = navigationAction.navigationType == .other
                && MermaidNavigationPolicy.allowsInitialDocument(
                    navigationAction.request.url,
                    isMainFrame: navigationAction.targetFrame?.isMainFrame == true
                )
            decisionHandler(allowed ? .allow : .cancel)
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            fail(error.localizedDescription)
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            fail(error.localizedDescription)
        }

        func webViewWebContentProcessDidTerminate(_: WKWebView) {
            fail("Mermaid renderer process terminated unexpectedly.")
        }

        func fail(_ detail: String) {
            DiagnosticsLogger.log(
                "Mermaid rendering failed",
                level: .warning,
                category: .chat,
                metadata: ["detail": detail]
            )
            DispatchQueue.main.async {
                self.parent.renderError = detail
                self.parent.onLayoutChange?()
            }
        }
    }
}

private extension String {
    var mermaidJSONStringLiteral: String {
        guard let data = try? JSONEncoder().encode(self),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }
        return encoded.replacingOccurrences(of: "</", with: "<\\/")
    }
}
