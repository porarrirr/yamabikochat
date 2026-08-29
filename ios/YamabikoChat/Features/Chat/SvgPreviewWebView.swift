import Foundation
import SwiftUI
import WebKit

enum SvgPreviewSanitizer {
    static func sanitize(_ svgContent: String) -> String {
        var sanitized = svgContent
        sanitized = replacePattern(
            "(?is)<script[^>]*>.*?</script>",
            in: sanitized,
            with: ""
        )
        sanitized = replacePattern(
            "(?is)<foreignObject[^>]*>.*?</foreignObject>",
            in: sanitized,
            with: ""
        )
        sanitized = replacePattern(
            "(?i)\\son\\w+\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)",
            in: sanitized,
            with: ""
        )
        sanitized = replacePattern(
            "(?i)javascript:",
            in: sanitized,
            with: ""
        )

        sanitized = replaceMatches(
            pattern: "(?i)\\b(xlink:href|href)\\s*=\\s*(['\"])(.*?)\\2",
            in: sanitized
        ) { match, original in
            let attribute = original.substring(with: match.range(at: 1))
            let value = original.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
            return value.hasPrefix("#") ? "\(attribute)=\"\(value)\"" : ""
        }

        sanitized = replaceMatches(
            pattern: "(?i)url\\(([^)]+)\\)",
            in: sanitized
        ) { match, original in
            let rawValue = original.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return rawValue.hasPrefix("#") ? "url(\(rawValue))" : "none"
        }

        return ensureNamespaces(sanitized)
    }

    private static func ensureNamespaces(_ svgContent: String) -> String {
        guard let svgTagRange = svgContent.range(
            of: "<svg\\b[^>]*>",
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return svgContent
        }

        var amended = String(svgContent[svgTagRange])
        let hasXmlns = amended.range(of: "xmlns\\s*=", options: [.regularExpression, .caseInsensitive]) != nil
        let hasXlink = amended.range(of: "xmlns:xlink\\s*=", options: [.regularExpression, .caseInsensitive]) != nil

        if !hasXmlns, let start = amended.range(of: "<svg", options: .caseInsensitive) {
            amended.replaceSubrange(
                start,
                with: "<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\""
            )
        } else if !hasXlink {
            if let closeIndex = amended.lastIndex(of: ">") {
                amended.replaceSubrange(
                    closeIndex ... closeIndex,
                    with: " xmlns:xlink=\"http://www.w3.org/1999/xlink\">"
                )
            }
        }

        var result = svgContent
        result.replaceSubrange(svgTagRange, with: amended)
        return result
    }

    private static func replacePattern(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func replaceMatches(
        pattern: String,
        in text: String,
        transform: (_ match: NSTextCheckingResult, _ original: NSString) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }
        let original = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: original.length))
        guard !matches.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            mutable.replaceCharacters(in: match.range, with: transform(match, original))
        }
        return mutable as String
    }
}

enum SvgPreviewHTMLBuilder {
    static let previewRootID = "yamabiko-svg-preview-root"

    static func buildHTML(svgContent: String, maxHeight: CGFloat, allowsZoom: Bool = false) -> String {
        let viewport = allowsZoom
            ? "width=device-width, initial-scale=1, maximum-scale=5, user-scalable=yes"
            : "width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no"
        let svgSizing = allowsZoom
            ? "width: auto; max-width: 100%; max-height: calc(100vh - 24px); height: auto;"
            : "width: 100%; max-width: 100%; max-height: \(Int(maxHeight))px; height: auto;"

        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="\(viewport)" />
          <meta name="color-scheme" content="light dark" />
          <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; connect-src 'none'; media-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'" />
          <style>
            html, body {
              margin: 0;
              padding: 0;
              background: transparent;
            }
            body {
              min-height: 0;
            }
            #\(previewRootID) {
              display: flex;
              align-items: flex-start;
              justify-content: center;
              padding: 12px;
              box-sizing: border-box;
            }
            svg {
              display: block;
              \(svgSizing)
            }
          </style>
        </head>
        <body>
          <div id="\(previewRootID)">
            \(svgContent)
          </div>
        </body>
        </html>
        """
    }
}

enum SvgPreviewHeightBridge {
    static let messageName = "svgPreviewContentHeight"

    static let measurementScript = """
    (() => {
      const root = document.getElementById('\(SvgPreviewHTMLBuilder.previewRootID)');
      if (!root) return;

      let lastHeight = 0;
      const reportHeight = () => {
        const height = Math.ceil(root.getBoundingClientRect().height);
        if (height <= 0 || height === lastHeight) return;
        lastHeight = height;
        window.webkit.messageHandlers.\(messageName).postMessage(height);
      };

      new ResizeObserver(reportHeight).observe(root);
      reportHeight();
    })();
    """
}

struct SvgPreviewWebView: UIViewRepresentable {
    let svgContent: String
    var maxHeight: CGFloat = 260
    var allowsInteraction = false
    var onHeightChange: ((CGFloat) -> Void)? = nil
    var onError: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onHeightChange: onHeightChange, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.addUserScript(WKUserScript(
            source: SvgPreviewHeightBridge.measurementScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        userContentController.add(context.coordinator, name: SvgPreviewHeightBridge.messageName)
        let configuration = YamabikoWebKitSupport.makeConfiguration(
            userContentController: userContentController
        )
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = allowsInteraction
        webView.scrollView.bounces = allowsInteraction
        webView.scrollView.pinchGestureRecognizer?.isEnabled = allowsInteraction
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onHeightChange = onHeightChange
        context.coordinator.onError = onError
        webView.scrollView.isScrollEnabled = allowsInteraction
        webView.scrollView.bounces = allowsInteraction
        webView.scrollView.pinchGestureRecognizer?.isEnabled = allowsInteraction
        guard context.coordinator.shouldRender(
            svgContent: svgContent,
            maxHeight: maxHeight,
            allowsInteraction: allowsInteraction
        ) else { return }
        let sanitized = SvgPreviewSanitizer.sanitize(svgContent)
        let html = SvgPreviewHTMLBuilder.buildHTML(
            svgContent: sanitized,
            maxHeight: maxHeight,
            allowsZoom: allowsInteraction
        )
        guard context.coordinator.lastHTML != html else { return }

        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: SvgPreviewHeightBridge.messageName
        )
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var onHeightChange: ((CGFloat) -> Void)?
        var onError: ((String) -> Void)?
        var lastHTML: String?
        private var lastSVGContent: String?
        private var lastMaxHeight: CGFloat?
        private var lastAllowsInteraction: Bool?

        init(onHeightChange: ((CGFloat) -> Void)?, onError: ((String) -> Void)?) {
            self.onHeightChange = onHeightChange
            self.onError = onError
        }

        func shouldRender(svgContent: String, maxHeight: CGFloat, allowsInteraction: Bool) -> Bool {
            guard lastSVGContent != svgContent
                    || lastMaxHeight != maxHeight
                    || lastAllowsInteraction != allowsInteraction
            else { return false }
            lastSVGContent = svgContent
            lastMaxHeight = maxHeight
            lastAllowsInteraction = allowsInteraction
            return true
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == SvgPreviewHeightBridge.messageName,
                  let value = message.body as? NSNumber
            else { return }
            reportContentHeight(CGFloat(truncating: value))
        }

        private func reportContentHeight(_ height: CGFloat) {
            guard height.isFinite, height > 0 else { return }
            let measuredHeight = max(44, height.rounded(.up))
            DispatchQueue.main.async { [weak self] in
                self?.onHeightChange?(measuredHeight)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            let scheme = url.scheme?.lowercased() ?? ""
            if scheme == "about" || scheme == "data" {
                decisionHandler(.allow)
            } else {
                decisionHandler(.cancel)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            fail(error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            fail(error.localizedDescription)
        }

        func webViewWebContentProcessDidTerminate(_: WKWebView) {
            fail("SVG renderer process terminated unexpectedly.")
        }

        private func fail(_ detail: String) {
            DiagnosticsLogger.log(
                "SVG rendering failed",
                level: .warning,
                category: .chat,
                metadata: ["detail": detail]
            )
            DispatchQueue.main.async { [weak self] in
                self?.onError?(detail)
            }
        }
    }
}

struct SvgDiagramView: View {
    let source: String
    var expanded = false
    var onExpand: (() -> Void)?
    var onLayoutChange: (() -> Void)?

    @State private var measuredHeight: CGFloat = 180
    @State private var renderError: String?

    private let inlineMaximumHeight: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !expanded {
                HStack(spacing: 12) {
                    Text("SVG")
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
                    Label(L10n.text("SVGを描画できません"), systemImage: "exclamationmark.triangle")
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
                    SvgPreviewWebView(
                        svgContent: source,
                        maxHeight: inlineMaximumHeight,
                        allowsInteraction: expanded,
                        onHeightChange: { height in
                            guard abs(measuredHeight - height) > 1 else { return }
                            measuredHeight = height
                            onLayoutChange?()
                        },
                        onError: { error in
                            renderError = error
                            onLayoutChange?()
                        }
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
                            .accessibilityLabel(Text(L10n.text("SVGを拡大")))
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
        }
        .background(Color(uiColor: expanded ? .systemBackground : .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: expanded ? 0 : 12, style: .continuous))
    }
}
