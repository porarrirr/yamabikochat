import SwiftUI
import WebKit
import UIKit

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
    private static let fallbackMarkdownRendererScript = """
    window.yamabikoRenderMarkdown = function(source) {
      var escaped = String(source || "")
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");
      return escaped.replace(/\\n/g, "<br/>");
    };
    """
    private static let markdownRendererScript: String = {
        guard let url = Bundle.main.url(forResource: "markdown-renderer", withExtension: "js", subdirectory: "mathjax"),
              let script = try? String(contentsOf: url, encoding: .utf8),
              !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return fallbackMarkdownRendererScript
        }
        return script
    }()

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

        let markdownPayload = markdownText.jsonStringLiteral

        let mathJaxScriptTag: String
        if let localURL = Bundle.main.url(forResource: "tex-svg", withExtension: "js", subdirectory: "mathjax") {
            mathJaxScriptTag = "<script src=\"\(localURL.absoluteString)\"></script>"
        } else {
            mathJaxScriptTag = "<script src=\"https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js\"></script>"
        }

        let bodyTextColor = colorScheme == .dark ? "#F2F2F7" : "#1C1C1E"
        let codeBackgroundColor = colorScheme == .dark ? "#1F1F23" : "#F4F4F8"
        let borderColor = colorScheme == .dark ? "#38383A" : "#E5E5EA"
        let linkColor = colorScheme == .dark ? "#70A7FF" : "#1F64E0"

        let html = """
        <html>
        <head>
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
          <meta name=\"color-scheme\" content=\"light dark\" />
          <script>
            window.MathJax = {
              tex: {
                inlineMath: [['$', '$'], ['\\\\(', '\\\\)']],
                displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']]
              },
              svg: { fontCache: 'global' }
            };
          </script>
          \(mathJaxScriptTag)
          <script>\(Self.markdownRendererScript)</script>
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
            #yamabiko-markdown > :first-child { margin-top: 0; }
            #yamabiko-markdown > :last-child { margin-bottom: 0; }
            h1, h2, h3, h4, h5, h6 { margin: 0.9em 0 0.4em 0; line-height: 1.2; }
            p { margin: 0.45em 0; }
            ul, ol { margin: 0.45em 0; padding-left: 1.35em; }
            li { margin: 0.2em 0; }
            blockquote {
              margin: 0.55em 0;
              border-left: 3px solid \(borderColor);
              padding: 0.2em 0 0.2em 0.8em;
              color: \(bodyTextColor);
              opacity: 0.9;
            }
            pre {
              margin: 0.6em 0;
              padding: 0.7em 0.8em;
              border-radius: 8px;
              background: \(codeBackgroundColor);
              border: 1px solid \(borderColor);
              overflow-x: auto;
            }
            code, pre { font-family: Menlo, ui-monospace, monospace; }
            code {
              background: \(codeBackgroundColor);
              border: 1px solid \(borderColor);
              border-radius: 6px;
              padding: 0.08em 0.35em;
              font-size: 0.92em;
            }
            pre code {
              background: transparent;
              border: none;
              padding: 0;
            }
            hr {
              border: none;
              border-top: 1px solid \(borderColor);
              margin: 0.9em 0;
            }
            a { color: \(linkColor); text-decoration: underline; }
          </style>
        </head>
        <body>
          <div id=\"yamabiko-markdown\"></div>
          <script>
            (function() {
              var source = \(markdownPayload);
              var root = document.getElementById('yamabiko-markdown');
              if (!root) return;
              if (typeof window.yamabikoRenderMarkdown === 'function') {
                root.innerHTML = window.yamabikoRenderMarkdown(source);
              } else {
                root.textContent = source || '';
              }
              var finish = function() {
                if (window.__yamabikoSendHeight) window.__yamabikoSendHeight();
              };
              if (window.MathJax && window.MathJax.typesetPromise) {
                window.MathJax.typesetPromise([root]).then(finish).catch(finish);
              } else {
                finish();
              }
            })();
          </script>
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

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.navigationType == .linkActivated,
                  let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https"
            else {
                decisionHandler(.allow)
                return
            }

            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
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

private extension String {
    var jsonStringLiteral: String {
        guard let data = try? JSONEncoder().encode(self),
              let encoded = String(data: data, encoding: .utf8)
        else {
            return "\"\""
        }
        return encoded.replacingOccurrences(of: "</", with: "<\\/")
    }
}
