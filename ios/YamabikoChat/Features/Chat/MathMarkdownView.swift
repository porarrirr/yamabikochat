import SwiftUI
import WebKit
import UIKit
import Foundation

enum MathMarkdownNormalizer {
    static func normalizeEscapedMathIfNeeded(_ markdown: String, mathRenderingEnabled: Bool) -> String {
        guard mathRenderingEnabled else { return markdown }
        guard containsMathDelimitersOutsideCode(markdown) else { return markdown }

        let unescaped = normalizeEscapedSequencesOutsideCode(markdown)
        return normalizeEscapedDollarDelimiters(unescaped)
    }

    static func normalizeEscapedDollarDelimiters(_ markdown: String) -> String {
        transformOutsideCode(markdown) { segment in
            normalizeEscapedDollarPairs(in: segment)
        }
    }

    private static func containsMathDelimitersOutsideCode(_ markdown: String) -> Bool {
        var hasMathDelimiter = false
        _ = transformOutsideCode(markdown) { segment in
            guard !hasMathDelimiter else { return segment }
            if segment.contains("$$") ||
                segment.contains("$") ||
                segment.contains(#"\("#) ||
                segment.contains(#"\)"#) ||
                segment.contains(#"\["#) ||
                segment.contains(#"\]"#) ||
                segment.contains(#"\$"#)
            {
                hasMathDelimiter = true
            }
            return segment
        }
        return hasMathDelimiter
    }

    private static func normalizeEscapedSequencesOutsideCode(_ markdown: String) -> String {
        transformOutsideCode(markdown) { segment in
            normalizeEscapedSequences(in: segment)
        }
    }

    private static func normalizeEscapedSequences(in text: String) -> String {
        text
            .replacingOccurrences(of: #"\\n"#, with: "\n")
            .replacingOccurrences(of: #"\\r"#, with: "\r")
            .replacingOccurrences(of: #"\\t"#, with: "\t")
            .replacingOccurrences(of: #"\\("#, with: #"\("#)
            .replacingOccurrences(of: #"\\)"#, with: #"\)"#)
            .replacingOccurrences(of: #"\\["#, with: #"\["#)
            .replacingOccurrences(of: #"\\]"#, with: #"\]"#)
            .replacingOccurrences(of: #"\\$"#, with: #"\$"#)
    }

    private static func transformOutsideCode(_ markdown: String, transform: (String) -> String) -> String {
        guard !markdown.isEmpty else { return markdown }

        var output = ""
        var cursor = markdown.startIndex

        while cursor < markdown.endIndex {
            if markdown[cursor...].hasPrefix("```") {
                let fenceStart = cursor
                let searchStart = markdown.index(cursor, offsetBy: 3)
                if let closingRange = markdown[searchStart...].range(of: "```") {
                    output.append(contentsOf: markdown[fenceStart..<closingRange.upperBound])
                    cursor = closingRange.upperBound
                } else {
                    output.append(contentsOf: markdown[fenceStart...])
                    break
                }
                continue
            }

            if markdown[cursor] == "`" {
                let inlineStart = cursor
                let searchStart = markdown.index(after: cursor)
                if let closingTick = markdown[searchStart...].firstIndex(of: "`") {
                    let inlineEnd = markdown.index(after: closingTick)
                    output.append(contentsOf: markdown[inlineStart..<inlineEnd])
                    cursor = inlineEnd
                } else {
                    output.append(contentsOf: markdown[inlineStart...])
                    break
                }
                continue
            }

            let segmentStart = cursor
            while cursor < markdown.endIndex {
                if markdown[cursor...].hasPrefix("```") || markdown[cursor] == "`" {
                    break
                }
                cursor = markdown.index(after: cursor)
            }

            let segment = String(markdown[segmentStart..<cursor])
            output.append(transform(segment))
        }

        return output
    }

    private static func normalizeEscapedDollarPairs(in text: String) -> String {
        var normalized = replaceEscapedMathPairs(
            in: text,
            pattern: #"(?<!\\)\\\$([^$\n]+?)\\\$(?![A-Za-z0-9])"#
        )

        normalized = replaceEscapedMathPairs(
            in: normalized,
            pattern: #"(?<!\\)\\\$([^$\n]+?)\$(?![A-Za-z0-9])"#
        )

        return normalized
    }

    private static func replaceEscapedMathPairs(in text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard let fullRange = Range(match.range(at: 0), in: result),
                  let contentRange = Range(match.range(at: 1), in: result) else {
                continue
            }
            let content = result[contentRange]
            result.replaceSubrange(fullRange, with: "$\(content)$")
        }

        return result
    }
}

enum MathMarkdownHTMLBuilder {
    static func buildHTML(
        markdownPayload: String,
        markdownRendererScript: String,
        bodyTextColor: String,
        codeBackgroundColor: String,
        borderColor: String,
        linkColor: String,
        mathRenderingEnabled: Bool,
        mathJaxScriptTag: String,
        copyButtonLabel: String = "コピー",
        copiedButtonLabel: String = "コピー済み"
    ) -> String {
        let mathSetupScript: String
        let mathTypesetScript: String
        let copyLabelSetupScript = """
          <script>
            window.__yamabikoCopyButtonLabel = \(copyButtonLabel.jsonStringLiteral);
            window.__yamabikoCopiedButtonLabel = \(copiedButtonLabel.jsonStringLiteral);
          </script>
        """
        if mathRenderingEnabled {
            mathSetupScript = """
              <script>
                window.MathJax = {
                  tex: {
                    inlineMath: [['$', '$'], ['\\\\(', '\\\\)']],
                    displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']],
                    processEscapes: true,
                    processEnvironments: true
                  },
                  svg: { fontCache: 'global' }
                };
                window.__yamabikoMathJaxOnError = function() {
                  if (window.console && window.console.warn) {
                    window.console.warn('MathJax script failed to load.');
                  }
                  if (window.__yamabikoSendHeight) window.__yamabikoSendHeight();
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
          <meta charset=\"utf-8\" />
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
          <meta name=\"color-scheme\" content=\"light dark\" />
          \(copyLabelSetupScript)
          \(mathSetupScript)
          <script>\(markdownRendererScript)</script>
          <style>
            html, body { margin: 0; padding: 0; background: transparent; }
            body {
              font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
              font-size: 15px;
              line-height: 1.48;
              color: \(bodyTextColor);
              overflow-wrap: anywhere;
              word-break: break-word;
              -webkit-font-smoothing: antialiased;
            }
            #yamabiko-markdown {
              max-width: 100%;
            }
            #yamabiko-markdown > :first-child { margin-top: 0; }
            #yamabiko-markdown > :last-child { margin-bottom: 0; }
            strong { font-weight: 650; }
            em { font-style: italic; }
            mjx-container {
              max-width: 100%;
            }
            mjx-container[display="true"] {
              display: block;
              overflow-x: auto;
              overflow-y: hidden;
            }
            mjx-container svg {
              max-width: 100%;
              height: auto;
            }
            h1, h2, h3, h4, h5, h6 {
              margin: 1.05em 0 0.45em 0;
              line-height: 1.22;
              font-weight: 700;
            }
            h1 { font-size: 1.42em; }
            h2 { font-size: 1.28em; }
            h3 { font-size: 1.15em; }
            h4, h5, h6 { font-size: 1.04em; }
            p { margin: 0.55em 0; }
            ul, ol { margin: 0.55em 0; padding-left: 1.38em; }
            li { margin: 0.28em 0; padding-left: 0.08em; }
            li > p { margin: 0.28em 0; }
            blockquote {
              margin: 0.7em 0;
              border-left: 3px solid \(borderColor);
              padding: 0.25em 0 0.25em 0.85em;
              color: \(bodyTextColor);
              opacity: 0.84;
            }
            .yamabiko-code-block {
              position: relative;
              margin: 0.7em 0;
            }
            pre {
              margin: 0.7em 0;
              padding: 0.8em 0.9em;
              border-radius: 8px;
              background: \(codeBackgroundColor);
              border: 1px solid \(borderColor);
              overflow-x: auto;
              line-height: 1.45;
            }
            .yamabiko-code-block pre {
              margin: 0;
              padding-top: 2.2em;
            }
            .yamabiko-copy-button {
              position: absolute;
              top: 0.45em;
              right: 0.45em;
              min-width: 4.8em;
              padding: 0.22em 0.55em;
              border-radius: 6px;
              border: 1px solid \(borderColor);
              background: \(codeBackgroundColor);
              color: \(bodyTextColor);
              font-size: 11px;
              line-height: 1.2;
              cursor: pointer;
              -webkit-appearance: none;
            }
            .yamabiko-copy-button:active {
              opacity: 0.72;
            }
            code, pre { font-family: Menlo, ui-monospace, monospace; }
            code {
              background: \(codeBackgroundColor);
              border: 1px solid \(borderColor);
              border-radius: 6px;
              padding: 0.1em 0.34em;
              font-size: 0.91em;
            }
            pre code {
              background: transparent;
              border: none;
              padding: 0;
              font-size: 0.9em;
            }
            hr {
              border: none;
              border-top: 1px solid \(borderColor);
              margin: 1em 0;
            }
            .yamabiko-table-wrap {
              margin: 0.75em 0;
              max-width: 100%;
              overflow-x: auto;
              overflow-y: hidden;
              -webkit-overflow-scrolling: touch;
              touch-action: pan-x pan-y;
              overscroll-behavior-x: contain;
              scrollbar-width: thin;
            }
            .yamabiko-table-wrap mjx-container,
            .yamabiko-table-wrap mjx-container svg {
              max-width: none;
            }
            table {
              border-collapse: collapse;
              width: max-content;
              min-width: 100%;
              table-layout: auto;
              border: 0;
            }
            th, td {
              min-width: 8.5em;
              max-width: 18em;
              border: 0;
              border-bottom: 1px solid \(borderColor);
              padding: 0.72em 0.7em;
              vertical-align: top;
              white-space: normal;
              overflow-wrap: anywhere;
              word-break: normal;
              font-weight: 400;
            }
            th {
              background: transparent;
              font-weight: 600;
            }
            table strong { font-weight: 600; }
            a {
              color: \(linkColor);
              text-decoration-line: underline;
              text-decoration-style: dotted;
              text-underline-offset: 0.16em;
              text-decoration-thickness: 1px;
            }
            .yamabiko-external-arrow {
              display: inline-block;
              margin-left: 0.12em;
              text-decoration: none;
            }
          </style>
        </head>
        <body>
          <div id=\"yamabiko-markdown\"></div>
          <script>
            (function() {
              var source = \(markdownPayload);
              var root = document.getElementById('yamabiko-markdown');
              if (!root) return;
              var copyLabel = window.__yamabikoCopyButtonLabel || 'Copy';
              var copiedLabel = window.__yamabikoCopiedButtonLabel || 'Copied';
              var renderGeneration = 0;
              function setCopyButtonLabel(button, label) {
                if (!button) return;
                button.textContent = label;
                button.setAttribute('aria-label', label);
              }
              function copyCodeText(text) {
                var payload = String(text || '');
                if (
                  window.webkit &&
                  window.webkit.messageHandlers &&
                  window.webkit.messageHandlers.copyCodeBlock &&
                  window.webkit.messageHandlers.copyCodeBlock.postMessage
                ) {
                  window.webkit.messageHandlers.copyCodeBlock.postMessage(payload);
                  return Promise.resolve();
                }
                if (window.navigator && window.navigator.clipboard && window.navigator.clipboard.writeText) {
                  return window.navigator.clipboard.writeText(payload);
                }
                return Promise.reject(new Error('copy unavailable'));
              }
              root.addEventListener('click', function(event) {
                var target = event.target;
                if (!target || !target.classList || !target.classList.contains('yamabiko-copy-button')) return;
                event.preventDefault();
                var container = target.closest('.yamabiko-code-block');
                if (!container) return;
                var codeElement = container.querySelector('pre > code');
                if (!codeElement) return;
                copyCodeText(codeElement.textContent || '').then(function() {
                  setCopyButtonLabel(target, copiedLabel);
                  if (target.__yamabikoCopyTimer) {
                    clearTimeout(target.__yamabikoCopyTimer);
                  }
                  target.__yamabikoCopyTimer = setTimeout(function() {
                    setCopyButtonLabel(target, copyLabel);
                    target.__yamabikoCopyTimer = null;
                  }, 1200);
                }).catch(function() {
                  setCopyButtonLabel(target, copyLabel);
                });
              });
              function enableHorizontalScrollContainers() {
                var selector = '.yamabiko-table-wrap, pre, mjx-container[display="true"]';
                var containers = document.querySelectorAll(selector);
                containers.forEach(function(element) {
                  if (element.__yamabikoHorizontalScrollBound) return;
                  element.__yamabikoHorizontalScrollBound = true;
                  var scrollGain = 1.6;
                  var touchStartX = 0;
                  var touchStartY = 0;
                  var scrollLeftStart = 0;
                  var isHorizontalScroll = false;
                  var lastTouchX = 0;
                  var lastTouchTime = 0;
                  var horizontalVelocity = 0;
                  var momentumFrame = 0;
                  function maximumScrollLeft() {
                    return Math.max(0, element.scrollWidth - element.clientWidth);
                  }
                  function clampScrollLeft(value) {
                    return Math.max(0, Math.min(maximumScrollLeft(), value));
                  }
                  function stopMomentum() {
                    if (momentumFrame) {
                      cancelAnimationFrame(momentumFrame);
                      momentumFrame = 0;
                    }
                  }
                  function startMomentum() {
                    stopMomentum();
                    var velocity = horizontalVelocity;
                    if (Math.abs(velocity) < 0.08) return;
                    var previousTime = performance.now();
                    function step(now) {
                      var elapsed = Math.min(32, Math.max(1, now - previousTime));
                      previousTime = now;
                      var previousLeft = element.scrollLeft;
                      var nextLeft = clampScrollLeft(previousLeft + velocity * elapsed);
                      element.scrollLeft = nextLeft;
                      velocity *= Math.pow(0.94, elapsed / 16.67);
                      if (
                        Math.abs(velocity) < 0.02 ||
                        (nextLeft === previousLeft && (nextLeft === 0 || nextLeft === maximumScrollLeft()))
                      ) {
                        momentumFrame = 0;
                        return;
                      }
                      momentumFrame = requestAnimationFrame(step);
                    }
                    momentumFrame = requestAnimationFrame(step);
                  }
                  element.addEventListener('touchstart', function(e) {
                    if (!e.touches || !e.touches.length) return;
                    stopMomentum();
                    touchStartX = e.touches[0].clientX;
                    touchStartY = e.touches[0].clientY;
                    lastTouchX = touchStartX;
                    lastTouchTime = performance.now();
                    scrollLeftStart = element.scrollLeft;
                    isHorizontalScroll = false;
                    horizontalVelocity = 0;
                  }, { passive: true });
                  element.addEventListener('touchmove', function(e) {
                    if (!e.touches || !e.touches.length) return;
                    var touchX = e.touches[0].clientX;
                    var touchY = e.touches[0].clientY;
                    var dx = touchX - touchStartX;
                    var dy = touchY - touchStartY;
                    if (!isHorizontalScroll) {
                      if (Math.abs(dx) < 4 && Math.abs(dy) < 4) return;
                      isHorizontalScroll = Math.abs(dx) > Math.abs(dy);
                    }
                    if (isHorizontalScroll && element.scrollWidth > element.clientWidth) {
                      var now = performance.now();
                      var elapsed = Math.max(1, now - lastTouchTime);
                      var delta = (lastTouchX - touchX) * scrollGain;
                      element.scrollLeft = clampScrollLeft(scrollLeftStart - dx * scrollGain);
                      horizontalVelocity = delta / elapsed;
                      lastTouchX = touchX;
                      lastTouchTime = now;
                      e.preventDefault();
                    }
                  }, { passive: false });
                  element.addEventListener('touchend', function() {
                    if (isHorizontalScroll) startMomentum();
                    isHorizontalScroll = false;
                  }, { passive: true });
                  element.addEventListener('touchcancel', function() {
                    isHorizontalScroll = false;
                    horizontalVelocity = 0;
                  }, { passive: true });
                });
              }
              window.__yamabikoEnableHorizontalScroll = enableHorizontalScrollContainers;
              function typesetRenderedContent(renderRoot, completion) {
                var root = renderRoot;
                var finish = completion;
        \(mathTypesetScript)
              }
              window.__yamabikoRenderSource = function(nextSource) {
                renderGeneration += 1;
                var generation = renderGeneration;
                source = String(nextSource || '');
                if (window.MathJax && window.MathJax.typesetClear) {
                  try {
                    window.MathJax.typesetClear([root]);
                  } catch (_) {}
                }
                if (typeof window.yamabikoRenderMarkdown === 'function') {
                  root.innerHTML = window.yamabikoRenderMarkdown(source);
                } else {
                  root.textContent = source || '';
                }
                typesetRenderedContent(root, function() {
                  if (generation !== renderGeneration) return;
                  enableHorizontalScrollContainers();
                  if (window.__yamabikoSendHeight) window.__yamabikoSendHeight();
                });
              };
              window.__yamabikoRenderSource(source);
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

struct MathJaxLoadPlan {
    let scriptTag: String
    let baseURL: URL?
}

enum MathJaxLoadPlanner {
    static func plan(
        mathRenderingEnabled: Bool,
        localScriptURL: URL?,
        logger: (String) -> Void = { _ in }
    ) -> MathJaxLoadPlan {
        guard mathRenderingEnabled else {
            return MathJaxLoadPlan(scriptTag: "", baseURL: nil)
        }

        let onErrorHandler = "window.__yamabikoMathJaxOnError && window.__yamabikoMathJaxOnError();"
        if let localScriptURL {
            return MathJaxLoadPlan(
                scriptTag: "<script src=\"tex-svg.js\" onerror=\"\(onErrorHandler)\"></script>",
                baseURL: localScriptURL.deletingLastPathComponent()
            )
        }

        logger("MathJax local script missing; math rendering disabled for this message.")
        return MathJaxLoadPlan(
            scriptTag: "",
            baseURL: nil
        )
    }
}

private enum MathMarkdownDiagnostics {
    static func logWarning(_ message: String) {
        DispatchQueue.main.async {
            DiagnosticsLogger.log(message, level: .warning, category: .chat)
        }
    }
}

enum MathMarkdownHeightScript {
    static func source(messageName: String) -> String {
        """
        (function() {
          function sendHeight() {
            if (window.__yamabikoEnableHorizontalScroll) {
              window.__yamabikoEnableHorizontalScroll();
            }
            var body = document.body;
            var root = document.getElementById('yamabiko-markdown');
            if (!body || !root || !window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.\(messageName)) {
              return;
            }
            var rect = root.getBoundingClientRect();
            var height = Math.max(
              root.scrollHeight || 0,
              root.offsetHeight || 0,
              rect && isFinite(rect.height) ? rect.height : 0
            );
            if (!isFinite(height) || height <= 0) {
              height = Math.max(body.scrollHeight || 0, body.offsetHeight || 0);
            }
            window.webkit.messageHandlers.\(messageName).postMessage(Math.ceil(height));
          }
          window.__yamabikoSendHeight = sendHeight;
          window.addEventListener('load', function() {
            sendHeight();
            setTimeout(sendHeight, 80);
            setTimeout(sendHeight, 220);
            setTimeout(sendHeight, 420);
          });
          window.addEventListener('resize', sendHeight);
          if (window.ResizeObserver) {
            var observer = new ResizeObserver(function() { sendHeight(); });
            var observedRoot = document.getElementById('yamabiko-markdown');
            if (observedRoot) observer.observe(observedRoot);
          }
          if (window.MutationObserver) {
            var mutationRoot = document.getElementById('yamabiko-markdown');
            if (mutationRoot) {
              var mutationObserver = new MutationObserver(function() { sendHeight(); });
              mutationObserver.observe(mutationRoot, { childList: true, subtree: true, characterData: true });
            }
          }
        })();
        """
    }
}

struct MathMarkdownView: View {
    private static let minimumHeight: CGFloat = 44

    let markdownText: String
    var mathRenderingEnabled: Bool = true
    var isStreaming: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var contentHeight: CGFloat = minimumHeight

    var body: some View {
        MathMarkdownWebView(
            markdownText: markdownText,
            mathRenderingEnabled: mathRenderingEnabled,
            isStreaming: isStreaming,
            colorScheme: colorScheme,
            measuredHeight: $contentHeight
        )
        .frame(height: max(Self.minimumHeight, contentHeight))
        .onChange(of: mathRenderingEnabled) { _, _ in
            contentHeight = Self.minimumHeight
        }
        .onChange(of: colorScheme) { _, _ in
            contentHeight = Self.minimumHeight
        }
    }
}

private struct MathMarkdownWebView: UIViewRepresentable {
    let markdownText: String
    let mathRenderingEnabled: Bool
    let isStreaming: Bool
    let colorScheme: ColorScheme
    @Binding var measuredHeight: CGFloat
    private static let fallbackMarkdownRendererScript = #"""
    (function(global) {
      "use strict";
      var copyButtonLabel = window.__yamabikoCopyButtonLabel || "Copy";
    
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

      function externalArrow() {
        return '<span class="yamabiko-external-arrow" aria-hidden="true">↗</span>';
      }

      function externalLinkHtml(safeUrl, label, labelAlreadyHasArrow) {
        var arrow = labelAlreadyHasArrow ? "" : " " + externalArrow();
        return '<a href="' + safeUrl + '">' + label + arrow + "</a>";
      }

      function bareUrlLabel(rawUrl) {
        var match = String(rawUrl || "").match(/^https?:\/\/(?:www\.)?([^\/?#:]+)(?::\d+)?/i);
        return match && match[1] ? match[1] : rawUrl;
      }

      function splitTrailingUrlPunctuation(rawUrl) {
        var url = String(rawUrl || "");
        var suffix = "";
        var alwaysTrailing = /[.,!?;:、。！？；：]$/;

        while (url && alwaysTrailing.test(url)) {
          suffix = url.slice(-1) + suffix;
          url = url.slice(0, -1);
        }

        var bracketPairs = [
          ["(", ")"], ["[", "]"], ["{", "}"],
          ["（", "）"], ["「", "」"], ["『", "』"]
        ];
        bracketPairs.forEach(function(pair) {
          var opening = pair[0];
          var closing = pair[1];
          while (url.charAt(url.length - 1) === closing) {
            var openings = url.split(opening).length - 1;
            var closings = url.split(closing).length - 1;
            if (closings <= openings) break;
            suffix = closing + suffix;
            url = url.slice(0, -1);
          }
        });

        return { url: url, suffix: suffix };
      }
    
      function isEscaped(text, index) {
        var backslashCount = 0;
        var cursor = index - 1;
        while (cursor >= 0 && text.charAt(cursor) === "\\") {
          backslashCount += 1;
          cursor -= 1;
        }
        return backslashCount % 2 === 1;
      }
    
      function findClosingDelimiter(text, startIndex, openDelimiter, closeDelimiter) {
        var cursor = startIndex + openDelimiter.length;
        while (cursor < text.length) {
          if (
            text.slice(cursor, cursor + closeDelimiter.length) === closeDelimiter &&
            !isEscaped(text, cursor)
          ) {
            return cursor;
          }
          cursor += 1;
        }
        return -1;
      }
    
      function protectMathSegments(text) {
        var source = String(text || "");
        var tokens = [];
        var output = "";
        var i = 0;
    
        function pushToken(segment) {
          var key = "@@YBMATH" + tokens.length + "@@";
          tokens.push(segment);
          output += key;
        }
    
        while (i < source.length) {
          if (source.slice(i, i + 2) === "$$" && !isEscaped(source, i)) {
            var blockClose = findClosingDelimiter(source, i, "$$", "$$");
            if (blockClose > i + 1) {
              pushToken(source.slice(i, blockClose + 2));
              i = blockClose + 2;
              continue;
            }
          }
    
          if (source.slice(i, i + 2) === "\\[" && !isEscaped(source, i)) {
            var bracketClose = findClosingDelimiter(source, i, "\\[", "\\]");
            if (bracketClose !== -1) {
              pushToken(source.slice(i, bracketClose + 2));
              i = bracketClose + 2;
              continue;
            }
          }
    
          if (source.slice(i, i + 2) === "\\(" && !isEscaped(source, i)) {
            var parenClose = findClosingDelimiter(source, i, "\\(", "\\)");
            if (parenClose !== -1) {
              pushToken(source.slice(i, parenClose + 2));
              i = parenClose + 2;
              continue;
            }
          }
    
          if (source.charAt(i) === "$" && !isEscaped(source, i) && source.charAt(i + 1) !== "$") {
            var inlineClose = i + 1;
            while (inlineClose < source.length) {
              if (
                source.charAt(inlineClose) === "$" &&
                !isEscaped(source, inlineClose) &&
                source.charAt(inlineClose - 1) !== "$" &&
                source.charAt(inlineClose + 1) !== "$"
              ) {
                break;
              }
              inlineClose += 1;
            }
    
            if (inlineClose < source.length && inlineClose > i + 1) {
              pushToken(source.slice(i, inlineClose + 1));
              i = inlineClose + 1;
              continue;
            }
          }
    
          output += source.charAt(i);
          i += 1;
        }
    
        return { text: output, tokens: tokens };
      }
    
      function applyInlineMarkdown(text) {
        var mathProtected = protectMathSegments(text);
        var input = mathProtected.text;
        if (!input) return "";
    
        var inlineBreakTokens = [];
        input = input.replace(/<br\s*\/?>/gi, function() {
          var key = "@@YBBR" + inlineBreakTokens.length + "@@";
          inlineBreakTokens.push("<br/>");
          return key;
        });
    
        var inlineCodeTokens = [];
        input = input.replace(/`([^`]+?)`/g, function(_, code) {
          var key = "@@YBCODE" + inlineCodeTokens.length + "@@";
          inlineCodeTokens.push("<code>" + escapeHtml(code) + "</code>");
          return key;
        });
    
        var inlineLinkTokens = [];
        input = input.replace(/\[([^\]]+)\]\(([^)]+)\)/g, function(_, label, href) {
          var safe = safeHref(href);
          var textLabel = escapeHtml(label || href);
          var key = "@@YBLINK" + inlineLinkTokens.length + "@@";
          if (!safe) {
            inlineLinkTokens.push(textLabel);
          } else {
            inlineLinkTokens.push(externalLinkHtml(safe, textLabel, /↗\s*$/.test(label || "")));
          }
          return key;
        });

        var bareLinkTokens = [];
        input = input.replace(/https?:\/\/[^\s<>"']+/gi, function(rawUrl) {
          var parts = splitTrailingUrlPunctuation(rawUrl);
          var safe = safeHref(parts.url);
          if (!safe) return rawUrl;
          var key = "@@YBBARELINK" + bareLinkTokens.length + "@@";
          var label = escapeHtml(bareUrlLabel(parts.url));
          bareLinkTokens.push(externalLinkHtml(safe, label, false));
          return key + parts.suffix;
        });
    
        var output = escapeHtml(input);
    
        output = output.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
        output = output.replace(/__([^_]+)__/g, "<strong>$1</strong>");
        output = output.replace(/\*([^*\n]+)\*/g, "<em>$1</em>");
        output = output.replace(/_([^_\n]+)_/g, "<em>$1</em>");
    
        output = output.replace(/@@YBLINK(\d+)@@/g, function(_, index) {
          return inlineLinkTokens[Number(index)] || "";
        });

        output = output.replace(/@@YBBARELINK(\d+)@@/g, function(_, index) {
          return bareLinkTokens[Number(index)] || "";
        });
    
        output = output.replace(/@@YBCODE(\d+)@@/g, function(_, index) {
          return inlineCodeTokens[Number(index)] || "";
        });
    
        output = output.replace(/@@YBBR(\d+)@@/g, function(_, index) {
          return inlineBreakTokens[Number(index)] || "";
        });
    
        output = output.replace(/@@YBMATH(\d+)@@/g, function(_, index) {
          return mathProtected.tokens[Number(index)] || "";
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
    
      function hasUnescapedPipe(text) {
        var value = String(text || "");
        for (var i = 0; i < value.length; i += 1) {
          if (value.charAt(i) === "|" && !isEscaped(value, i)) {
            return true;
          }
        }
        return false;
      }
    
      function splitTableRow(line) {
        var text = String(line || "").trim();
        if (!text) return [];
        if (text.charAt(0) === "|") text = text.slice(1);
        if (text.charAt(text.length - 1) === "|") text = text.slice(0, -1);
    
        var cells = [];
        var segmentStart = 0;
        for (var i = 0; i < text.length; i += 1) {
          if (text.charAt(i) === "|" && !isEscaped(text, i)) {
            cells.push(text.slice(segmentStart, i));
            segmentStart = i + 1;
          }
        }
        cells.push(text.slice(segmentStart));
    
        return cells.map(function(cell) {
          return cell.replace(/\\\|/g, "|").trim();
        });
      }
    
      function isDelimiterCell(cell) {
        var value = String(cell || "").trim();
        return /^:?-{3,}:?$/.test(value);
      }
    
      function parseAlignment(cell) {
        var value = String(cell || "").trim();
        if (/^:-{3,}:$/.test(value)) return "center";
        if (/^:-{3,}$/.test(value)) return "left";
        if (/^-{3,}:$/.test(value)) return "right";
        return null;
      }
    
      function normalizeCells(cells, columnCount) {
        var normalized = [];
        for (var i = 0; i < columnCount; i += 1) {
          normalized.push(String((cells && cells[i]) || "").trim());
        }
        return normalized;
      }
    
      function renderTableCell(tag, text, alignment) {
        var style = alignment ? ' style="text-align: ' + alignment + ';"' : "";
        return "<" + tag + style + ">" + applyInlineMarkdown(text) + "</" + tag + ">";
      }
    
      function parseTable(lines, startIndex) {
        if (startIndex + 1 >= lines.length) return null;
    
        var headerLine = lines[startIndex];
        var delimiterLine = lines[startIndex + 1];
        if (!hasUnescapedPipe(headerLine) || !hasUnescapedPipe(delimiterLine)) return null;
    
        var headerCells = splitTableRow(headerLine);
        var delimiterCells = splitTableRow(delimiterLine);
        if (!headerCells.length || delimiterCells.length < headerCells.length) return null;
        if (!delimiterCells.slice(0, headerCells.length).every(isDelimiterCell)) return null;
    
        var columnCount = headerCells.length;
        var alignments = delimiterCells.slice(0, columnCount).map(parseAlignment);
        var normalizedHeader = normalizeCells(headerCells, columnCount);
    
        var rowHtml = normalizedHeader.map(function(cell, index) {
          return renderTableCell("th", cell, alignments[index]);
        }).join("");
    
        var rows = [];
        var index = startIndex + 2;
        while (index < lines.length) {
          var line = lines[index];
          if (isBlank(line) || !hasUnescapedPipe(line)) break;
          var cells = splitTableRow(line);
          if (!cells.length) break;
          var normalizedCells = normalizeCells(cells, columnCount);
          rows.push("<tr>" + normalizedCells.map(function(cell, cellIndex) {
            return renderTableCell("td", cell, alignments[cellIndex]);
          }).join("") + "</tr>");
          index += 1;
        }
    
        return {
          html:
            "<div class=\"yamabiko-table-wrap\">" +
              "<table>" +
                "<thead><tr>" + rowHtml + "</tr></thead>" +
                "<tbody>" + rows.join("") + "</tbody>" +
              "</table>" +
            "</div>",
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
          codeBlocks.push(
            "<div class=\"yamabiko-code-block\">" +
              "<button type=\"button\" class=\"yamabiko-copy-button\">" + copyButtonLabel + "</button>" +
              "<pre><code" + classAttr + ">" + escapeHtml(code) + "</code></pre>" +
            "</div>"
          );
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
    
          var parsedTable = parseTable(lines, i);
          if (parsedTable) {
            flushParagraph();
            htmlParts.push(parsedTable.html);
            i = parsedTable.nextIndex;
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
            MathMarkdownDiagnostics.logWarning(message)
        }
    }()

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: Coordinator.heightMessageName)
        contentController.add(context.coordinator, name: Coordinator.copyMessageName)

        let userScript = WKUserScript(
            source: MathMarkdownHeightScript.source(messageName: Coordinator.heightMessageName),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(userScript)

        let config = YamabikoWebKitSupport.makeConfiguration(userContentController: contentController)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.delaysContentTouches = false
        webView.scrollView.isDirectionalLockEnabled = true
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self

        let normalizedMarkdown = MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(
            markdownText,
            mathRenderingEnabled: mathRenderingEnabled
        )
        let localMathJaxURL = MathMarkdownResourceResolver.mathJaxScriptURL(in: .main)
        let mathJaxLoadPlan = MathJaxLoadPlanner.plan(
            mathRenderingEnabled: mathRenderingEnabled,
            localScriptURL: localMathJaxURL
        ) { message in
            MathMarkdownDiagnostics.logWarning(message)
        }

        let bodyTextColor = colorScheme == .dark ? "#F2F2F7" : "#1C1C1E"
        let codeBackgroundColor = colorScheme == .dark ? "#1F1F23" : "#F4F4F8"
        let borderColor = colorScheme == .dark ? "#38383A" : "#E5E5EA"
        let linkColor = colorScheme == .dark ? "#70A7FF" : "#1F64E0"

        let html = MathMarkdownHTMLBuilder.buildHTML(
            markdownPayload: "\"\"",
            markdownRendererScript: Self.markdownRendererScript,
            bodyTextColor: bodyTextColor,
            codeBackgroundColor: codeBackgroundColor,
            borderColor: borderColor,
            linkColor: linkColor,
            mathRenderingEnabled: mathRenderingEnabled,
            mathJaxScriptTag: mathJaxLoadPlan.scriptTag,
            copyButtonLabel: L10n.text("コピー"),
            copiedButtonLabel: L10n.text("コピー済み")
        )

        let resourceDirectory = mathJaxLoadPlan.baseURL == nil
            ? nil
            : MathMarkdownWebResourceLoader.preparedResourceDirectory()
        context.coordinator.updateDocument(
            html: html,
            markdownPayload: normalizedMarkdown.jsonStringLiteral,
            isStreaming: isStreaming,
            resourceDirectory: resourceDirectory,
            in: webView
        )
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.heightMessageName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.copyMessageName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let heightMessageName = "contentHeight"
        static let copyMessageName = "copyCodeBlock"

        var parent: MathMarkdownWebView
        var lastHTML: String?
        private var pendingLoadToken = 0
        private var pendingRenderToken = 0
        private var didFinishInitialLoad = false
        private var pendingMarkdownPayload: String?
        private var pendingIsStreaming = false
        private var lastRenderedMarkdownPayload: String?
        private var lastRenderWasStreaming = false

        init(parent: MathMarkdownWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            didFinishInitialLoad = true
            if let payload = pendingMarkdownPayload {
                scheduleMarkdownRender(
                    payload,
                    isStreaming: pendingIsStreaming,
                    in: webView,
                    force: true
                )
            } else {
                requestHeightMeasurement(for: webView)
            }
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
            if message.name == Self.copyMessageName {
                if let codeText = message.body as? String {
                    UIPasteboard.general.string = codeText
                }
                return
            }

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

        func updateDocument(
            html: String,
            markdownPayload: String,
            isStreaming: Bool,
            resourceDirectory: URL?,
            in webView: WKWebView
        ) {
            pendingMarkdownPayload = markdownPayload
            pendingIsStreaming = isStreaming

            if lastHTML != html {
                lastHTML = html
                lastRenderedMarkdownPayload = nil
                lastRenderWasStreaming = false
                scheduleHTMLLoad(
                    html,
                    resourceDirectory: resourceDirectory,
                    in: webView
                )
                return
            }

            scheduleMarkdownRender(
                markdownPayload,
                isStreaming: isStreaming,
                in: webView,
                force: !isStreaming && lastRenderWasStreaming
            )
        }

        func scheduleHTMLLoad(_ html: String, resourceDirectory: URL?, in webView: WKWebView) {
            pendingLoadToken += 1
            pendingRenderToken += 1
            let token = pendingLoadToken
            didFinishInitialLoad = false
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView, token == self.pendingLoadToken, self.lastHTML == html else {
                    return
                }
                YamabikoWebKitSupport.loadHTMLDocument(
                    html,
                    resourceDirectory: resourceDirectory,
                    in: webView
                )
            }
        }

        func scheduleMarkdownRender(
            _ markdownPayload: String,
            isStreaming: Bool,
            in webView: WKWebView,
            force: Bool = false
        ) {
            pendingMarkdownPayload = markdownPayload
            pendingIsStreaming = isStreaming

            guard didFinishInitialLoad else { return }
            guard force || lastRenderedMarkdownPayload != markdownPayload else {
                scheduleHeightMeasurement(for: webView)
                return
            }

            pendingRenderToken += 1
            let token = pendingRenderToken
            let delay: TimeInterval = isStreaming ? 0.045 : 0
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak webView] in
                guard let self,
                      let webView,
                      token == self.pendingRenderToken,
                      self.pendingMarkdownPayload == markdownPayload
                else {
                    return
                }

                let script = "window.__yamabikoRenderSource && window.__yamabikoRenderSource(\(markdownPayload));"
                webView.evaluateJavaScript(script) { [weak self, weak webView] _, _ in
                    guard let self, token == self.pendingRenderToken else { return }
                    self.lastRenderedMarkdownPayload = markdownPayload
                    self.lastRenderWasStreaming = isStreaming
                    if let webView {
                        self.requestHeightMeasurement(for: webView)
                    }
                }
            }
        }

        func scheduleHeightMeasurement(for webView: WKWebView) {
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.requestHeightMeasurement(for: webView)
            }
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
