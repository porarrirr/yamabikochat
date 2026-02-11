import SwiftUI
import WebKit
import UIKit

enum MathMarkdownHTMLBuilder {
    static func buildHTML(
        markdownPayload: String,
        markdownRendererScript: String,
        bodyTextColor: String,
        codeBackgroundColor: String,
        borderColor: String,
        linkColor: String,
        mathRenderingEnabled: Bool,
        mathJaxScriptTag: String
    ) -> String {
        let mathSetupScript: String
        let mathTypesetScript: String
        if mathRenderingEnabled {
            mathSetupScript = """
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
            """
            mathTypesetScript = """
                  if (window.MathJax && window.MathJax.typesetPromise) {
                    window.MathJax.typesetPromise([root]).then(finish).catch(finish);
                  } else {
                    finish();
                  }
            """
        } else {
            mathSetupScript = ""
            mathTypesetScript = "finish();"
        }

        return """
        <html>
        <head>
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
          <meta name=\"color-scheme\" content=\"light dark\" />
          \(mathSetupScript)
          <script>\(markdownRendererScript)</script>
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
        \(mathTypesetScript)
            })();
          </script>
        </body>
        </html>
        """
    }
}

enum MathMarkdownResourceResolver {
    typealias ResourceLookup = (_ resource: String, _ ext: String, _ subdirectory: String?) -> URL?
    typealias ScriptLoader = (_ url: URL) -> String?

    static func resolveResourceURL(
        resource: String,
        withExtension ext: String,
        subdirectories: [String?],
        using lookup: ResourceLookup
    ) -> URL? {
        for subdirectory in subdirectories {
            if let url = lookup(resource, ext, subdirectory) {
                return url
            }
        }
        return nil
    }

    static func markdownRendererScript(
        in bundle: Bundle = .main,
        fallbackScript: String,
        logger: (String) -> Void = { _ in }
    ) -> String {
        markdownRendererScript(
            fallbackScript: fallbackScript,
            lookup: { resource, ext, subdirectory in
                bundle.url(forResource: resource, withExtension: ext, subdirectory: subdirectory)
            },
            scriptLoader: { url in
                try? String(contentsOf: url, encoding: .utf8)
            },
            logger: logger
        )
    }

    static func markdownRendererScript(
        fallbackScript: String,
        lookup: ResourceLookup,
        scriptLoader: ScriptLoader,
        logger: (String) -> Void = { _ in }
    ) -> String {
        guard let url = resolveResourceURL(
            resource: "markdown-renderer",
            withExtension: "js",
            subdirectories: ["mathjax", nil],
            using: lookup
        ),
        let script = scriptLoader(url),
        !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            logger("MathMarkdown renderer script missing; using built-in fallback renderer.")
            return fallbackScript
        }
        return script
    }

    static func mathJaxScriptURL(in bundle: Bundle = .main) -> URL? {
        resolveResourceURL(
            resource: "tex-svg",
            withExtension: "js",
            subdirectories: ["mathjax", nil],
            using: { resource, ext, subdirectory in
                bundle.url(forResource: resource, withExtension: ext, subdirectory: subdirectory)
            }
        )
    }
}

struct MathMarkdownView: View {
    let markdownText: String
    var mathRenderingEnabled: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    @State private var contentHeight: CGFloat = 44

    var body: some View {
        MathMarkdownWebView(
            markdownText: markdownText,
            mathRenderingEnabled: mathRenderingEnabled,
            colorScheme: colorScheme,
            measuredHeight: $contentHeight
        )
        .frame(height: max(44, contentHeight))
    }
}

private struct MathMarkdownWebView: UIViewRepresentable {
    let markdownText: String
    let mathRenderingEnabled: Bool
    let colorScheme: ColorScheme
    @Binding var measuredHeight: CGFloat
    private static let fallbackMarkdownRendererScript = #"""
    (function(global) {
      "use strict";

      function escapeHtml(value) {
        return String(value || "")
          .replace(/&/g, "&amp;")
          .replace(/</g, "&lt;")
          .replace(/>/g, "&gt;")
          .replace(/\"/g, "&quot;")
          .replace(/'/g, "&#39;");
      }

      function escapeAttr(value) {
        return escapeHtml(value).replace(/`/g, "&#96;");
      }

      function safeHref(rawUrl) {
        var url = String(rawUrl || "").trim();
        if (!url) return null;
        var unescaped = url.replace(/&amp;/g, "&");
        if (!/^https?:\/\//i.test(unescaped)) return null;
        return escapeAttr(unescaped);
      }

      function applyInlineMarkdown(text) {
        var input = String(text || "");
        if (!input) return "";

        var inlineCodeTokens = [];
        input = input.replace(/`([^`]+?)`/g, function(_, code) {
          var key = "@@INLINE_CODE_" + inlineCodeTokens.length + "@@";
          inlineCodeTokens.push("<code>" + escapeHtml(code) + "</code>");
          return key;
        });

        var inlineLinkTokens = [];
        input = input.replace(/\[([^\]]+)\]\(([^)]+)\)/g, function(_, label, href) {
          var safe = safeHref(href);
          var textLabel = escapeHtml(label || href);
          var key = "@@INLINE_LINK_" + inlineLinkTokens.length + "@@";
          if (!safe) {
            inlineLinkTokens.push(textLabel);
          } else {
            inlineLinkTokens.push('<a href="' + safe + '">' + textLabel + "</a>");
          }
          return key;
        });

        var output = escapeHtml(input);

        output = output.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
        output = output.replace(/__([^_]+)__/g, "<strong>$1</strong>");
        output = output.replace(/\*([^*\n]+)\*/g, "<em>$1</em>");
        output = output.replace(/_([^_\n]+)_/g, "<em>$1</em>");

        output = output.replace(/@@INLINE_LINK_(\d+)@@/g, function(_, index) {
          return inlineLinkTokens[Number(index)] || "";
        });

        output = output.replace(/@@INLINE_CODE_(\d+)@@/g, function(_, index) {
          return inlineCodeTokens[Number(index)] || "";
        });

        return output;
      }

      function isBlank(line) {
        return !line || !line.trim();
      }

      function renderParagraph(lines) {
        var content = lines.join(" ").trim();
        if (!content) return "";
        return "<p>" + applyInlineMarkdown(content) + "</p>";
      }

      function parseList(lines, startIndex, ordered) {
        var index = startIndex;
        var items = [];
        var pattern = ordered ? /^\s*\d+\.\s+(.*)$/ : /^\s*[-*+]\s+(.*)$/;

        while (index < lines.length) {
          var line = lines[index];
          var match = line.match(pattern);
          if (!match) break;
          items.push("<li>" + applyInlineMarkdown(match[1].trim()) + "</li>");
          index += 1;
        }

        var tag = ordered ? "ol" : "ul";
        return {
          html: "<" + tag + ">" + items.join("") + "</" + tag + ">",
          nextIndex: index
        };
      }

      function parseBlockquote(lines, startIndex) {
        var index = startIndex;
        var quoteLines = [];

        while (index < lines.length) {
          var line = lines[index];
          if (!/^\s*>/.test(line)) break;
          quoteLines.push(line.replace(/^\s*>\s?/, ""));
          index += 1;
        }

        return {
          html: "<blockquote>" + renderBlocks(quoteLines.join("\n")) + "</blockquote>",
          nextIndex: index
        };
      }

      function renderBlocks(input) {
        var source = String(input || "").replace(/\r\n?/g, "\n");
        var codeBlocks = [];

        source = source.replace(/```([^\n`]*)\n([\s\S]*?)```/g, function(_, language, code) {
          var key = "@@CODE_BLOCK_" + codeBlocks.length + "@@";
          var langClass = String(language || "").trim();
          var classAttr = langClass ? ' class="language-' + escapeAttr(langClass) + '"' : "";
          codeBlocks.push("<pre><code" + classAttr + ">" + escapeHtml(code) + "</code></pre>");
          return key;
        });

        var lines = source.split("\n");
        var htmlParts = [];
        var paragraphBuffer = [];

        function flushParagraph() {
          if (!paragraphBuffer.length) return;
          var paragraph = renderParagraph(paragraphBuffer);
          if (paragraph) htmlParts.push(paragraph);
          paragraphBuffer = [];
        }

        var i = 0;
        while (i < lines.length) {
          var line = lines[i];
          var trimmed = line.trim();

          if (isBlank(line)) {
            flushParagraph();
            i += 1;
            continue;
          }

          if (/^@@CODE_BLOCK_\d+@@$/.test(trimmed)) {
            flushParagraph();
            var codeIndex = Number(trimmed.replace(/\D/g, ""));
            htmlParts.push(codeBlocks[codeIndex] || "");
            i += 1;
            continue;
          }

          var heading = line.match(/^(#{1,6})\s+(.*)$/);
          if (heading) {
            flushParagraph();
            var level = heading[1].length;
            htmlParts.push("<h" + level + ">" + applyInlineMarkdown(heading[2].trim()) + "</h" + level + ">");
            i += 1;
            continue;
          }

          if (/^\s*([-*_])\1{2,}\s*$/.test(line)) {
            flushParagraph();
            htmlParts.push("<hr/>");
            i += 1;
            continue;
          }

          if (/^\s*>/.test(line)) {
            flushParagraph();
            var quote = parseBlockquote(lines, i);
            htmlParts.push(quote.html);
            i = quote.nextIndex;
            continue;
          }

          if (/^\s*[-*+]\s+/.test(line)) {
            flushParagraph();
            var unordered = parseList(lines, i, false);
            htmlParts.push(unordered.html);
            i = unordered.nextIndex;
            continue;
          }

          if (/^\s*\d+\.\s+/.test(line)) {
            flushParagraph();
            var ordered = parseList(lines, i, true);
            htmlParts.push(ordered.html);
            i = ordered.nextIndex;
            continue;
          }

          paragraphBuffer.push(line.trim());
          i += 1;
        }

        flushParagraph();
        return htmlParts.join("\n");
      }

      global.yamabikoRenderMarkdown = function(markdown) {
        return renderBlocks(markdown);
      };
    })(window);
    """#
    private static let markdownRendererScript: String = {
        MathMarkdownResourceResolver.markdownRendererScript(
            in: .main,
            fallbackScript: fallbackMarkdownRendererScript
        ) { message in
            DiagnosticsLogger.log(message, level: .warning, category: .chat)
        }
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
        if mathRenderingEnabled,
           let localURL = MathMarkdownResourceResolver.mathJaxScriptURL(in: .main) {
            mathJaxScriptTag = "<script src=\"\(localURL.absoluteString)\"></script>"
        } else if mathRenderingEnabled {
            mathJaxScriptTag = "<script src=\"https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js\"></script>"
        } else {
            mathJaxScriptTag = ""
        }

        let bodyTextColor = colorScheme == .dark ? "#F2F2F7" : "#1C1C1E"
        let codeBackgroundColor = colorScheme == .dark ? "#1F1F23" : "#F4F4F8"
        let borderColor = colorScheme == .dark ? "#38383A" : "#E5E5EA"
        let linkColor = colorScheme == .dark ? "#70A7FF" : "#1F64E0"

        let html = MathMarkdownHTMLBuilder.buildHTML(
            markdownPayload: markdownPayload,
            markdownRendererScript: Self.markdownRendererScript,
            bodyTextColor: bodyTextColor,
            codeBackgroundColor: codeBackgroundColor,
            borderColor: borderColor,
            linkColor: linkColor,
            mathRenderingEnabled: mathRenderingEnabled,
            mathJaxScriptTag: mathJaxScriptTag
        )

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
