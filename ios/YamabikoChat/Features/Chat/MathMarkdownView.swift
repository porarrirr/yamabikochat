import SwiftUI
import WebKit

struct MathMarkdownView: View {
    let markdownText: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var contentHeight: CGFloat = 44

    var body: some View {
        MathMarkdownWebView(
            markdownText: markdownText,
            colorScheme: colorScheme,
            measuredHeight: $contentHeight
        )
        .frame(height: max(44, contentHeight))
    }
}

private struct MathMarkdownWebView: UIViewRepresentable {
    let markdownText: String
    let colorScheme: ColorScheme
    @Binding var measuredHeight: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: Coordinator.heightMessageName)

        let resizeObserverScript = """
        (function() {
          function sendHeight() {
            var body = document.body;
            var doc = document.documentElement;
            if (!body || !doc || !window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.\(Coordinator.heightMessageName)) {
              return;
            }
            var height = Math.max(
              body.scrollHeight, body.offsetHeight,
              doc.clientHeight, doc.scrollHeight, doc.offsetHeight
            );
            window.webkit.messageHandlers.\(Coordinator.heightMessageName).postMessage(height);
          }
          window.__yamabikoSendHeight = sendHeight;
          window.addEventListener('load', function() {
            sendHeight();
            setTimeout(sendHeight, 80);
            setTimeout(sendHeight, 220);
            setTimeout(sendHeight, 420);
          });
          if (window.ResizeObserver) {
            var observer = new ResizeObserver(function() { sendHeight(); });
            observer.observe(document.documentElement);
          }
        })();
        """
        let userScript = WKUserScript(
            source: resizeObserverScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(userScript)

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self

        let escaped = markdownText
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br/>")

        let scriptTag: String
        if let localURL = Bundle.main.url(forResource: "tex-svg", withExtension: "js", subdirectory: "mathjax") {
            scriptTag = "<script src=\"\(localURL.absoluteString)\"></script>"
        } else {
            scriptTag = "<script src=\"https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js\"></script>"
        }

        let bodyTextColor = colorScheme == .dark ? "#F2F2F7" : "#1C1C1E"

        let html = """
        <html>
        <head>
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
          <meta name=\"color-scheme\" content=\"light dark\" />
          \(scriptTag)
          <style>
            html, body { margin: 0; padding: 0; background: transparent; }
            body {
              font-family: -apple-system;
              font-size: 15px;
              line-height: 1.35;
              color: \(bodyTextColor);
              overflow-wrap: anywhere;
              word-break: break-word;
            }
            code, pre { font-family: Menlo, monospace; }
          </style>
        </head>
        <body>
          \(escaped)
        </body>
        </html>
        """

        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        } else {
            context.coordinator.requestHeightMeasurement(for: webView)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.heightMessageName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let heightMessageName = "contentHeight"

        var parent: MathMarkdownWebView
        var lastHTML: String?

        init(parent: MathMarkdownWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            requestHeightMeasurement(for: webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak webView] in
                guard let webView else { return }
                self.requestHeightMeasurement(for: webView)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak webView] in
                guard let webView else { return }
                self.requestHeightMeasurement(for: webView)
            }
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.heightMessageName else { return }
            if let value = message.body as? NSNumber {
                apply(height: CGFloat(truncating: value))
            } else if let value = message.body as? Double {
                apply(height: CGFloat(value))
            }
        }

        func requestHeightMeasurement(for webView: WKWebView) {
            webView.evaluateJavaScript("window.__yamabikoSendHeight && window.__yamabikoSendHeight();", completionHandler: nil)
        }

        private func apply(height rawHeight: CGFloat) {
            let clamped = max(44, rawHeight.rounded(.up))
            DispatchQueue.main.async {
                guard abs(self.parent.measuredHeight - clamped) > 1 else { return }
                self.parent.measuredHeight = clamped
            }
        }
    }
}
