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
              font-family: -apple-system;
              font-size: 15px;
              line-height: 1.35;
              color: \(bodyTextColor);
              overflow-wrap: anywhere;
              word-break: break-word;
            }
            #yamabiko-markdown {
              max-width: 100%;
            }
            #yamabiko-markdown > :first-child { margin-top: 0; }
            #yamabiko-markdown > :last-child { margin-bottom: 0; }
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
            .yamabiko-code-block {
              position: relative;
              margin: 0.6em 0;
            }
            pre {
              margin: 0.6em 0;
              padding: 0.7em 0.8em;
              border-radius: 8px;
              background: \(codeBackgroundColor);
              border: 1px solid \(borderColor);
              overflow-x: auto;
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
            .yamabiko-table-wrap {
              margin: 0.6em 0;
              max-width: 100%;
              overflow-x: auto;
              overflow-y: hidden;
              -webkit-overflow-scrolling: touch;
              touch-action: pan-x pan-y;
              overscroll-behavior-x: contain;
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
              border: 1px solid \(borderColor);
            }
            th, td {
              border: 1px solid \(borderColor);
              padding: 0.4em 0.55em;
              vertical-align: top;
              white-space: normal;
              overflow-wrap: anywhere;
              word-break: normal;
            }
            th {
              background: \(codeBackgroundColor);
              font-weight: 600;
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
              var copyLabel = window.__yamabikoCopyButtonLabel || 'Copy';
              var copiedLabel = window.__yamabikoCopiedButtonLabel || 'Copied';
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
                  var touchStartX = 0;
                  var touchStartY = 0;
                  var scrollLeftStart = 0;
                  var isHorizontalScroll = false;
                  element.addEventListener('touchstart', function(e) {
                    if (!e.touches || !e.touches.length) return;
                    touchStartX = e.touches[0].clientX;
                    touchStartY = e.touches[0].clientY;
                    scrollLeftStart = element.scrollLeft;
                    isHorizontalScroll = false;
                  }, { passive: true });
                  element.addEventListener('touchmove', function(e) {
                    if (!e.touches || !e.touches.length) return;
                    var dx = e.touches[0].clientX - touchStartX;
                    var dy = e.touches[0].clientY - touchStartY;
                    if (!isHorizontalScroll) {
                      if (Math.abs(dx) < 4 && Math.abs(dy) < 4) return;
                      isHorizontalScroll = Math.abs(dx) > Math.abs(dy);
                    }
                    if (isHorizontalScroll && element.scrollWidth > element.clientWidth) {
                      element.scrollLeft = scrollLeftStart - dx;
                      e.preventDefault();
                    }
                  }, { passive: false });
                  element.addEventListener('touchend', function() {
                    isHorizontalScroll = false;
                  }, { passive: true });
                });
              }
              window.__yamabikoEnableHorizontalScroll = enableHorizontalScrollContainers;
              var finish = function() {
                enableHorizontalScrollContainers();
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

struct MathMarkdownView: View {
    private static let minimumHeight: CGFloat = 44

    let markdownText: String
    var mathRenderingEnabled: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    @State private var contentHeight: CGFloat = minimumHeight

    var body: some View {
        MathMarkdownWebView(
            markdownText: markdownText,
            mathRenderingEnabled: mathRenderingEnabled,
            colorScheme: colorScheme,
            measuredHeight: $contentHeight
        )
        .id("\(markdownText.hashValue)-\(mathRenderingEnabled)")
        .frame(height: max(Self.minimumHeight, contentHeight))
        .onChange(of: markdownText) { _, _ in
            contentHeight = Self.minimumHeight
        }
        .onChange(of: mathRenderingEnabled) { _, _ in
            contentHeight = Self.minimumHeight
        }
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
            inlineLinkTokens.push('<a href="' + safe + '">' + textLabel + "</a>");
          }
          return key;
        });
    
        var output = escapeHtml(input);
    
        output = output.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
        output = output.replace(/__([^_]+)__/g, "<strong>$1</strong>");
        output = output.replace(/\*([^*\n]+)\*/g, "<em>$1</em>");
        output = output.replace(/_([^_\n]+)_/g, "<em>$1</em>");
    
        output = output.replace(/@@YBLINK(\d+)@@/g, function(_, index) {
          return inlineLinkTokens[Number(index)] || "";
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
            DiagnosticsLogger.log(message, level: .warning, category: .chat)
        }
    }()

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: Coordinator.heightMessageName)
        contentController.add(context.coordinator, name: Coordinator.copyMessageName)

        let resizeObserverScript = """
        (function() {
          function sendHeight() {
            if (window.__yamabikoEnableHorizontalScroll) {
              window.__yamabikoEnableHorizontalScroll();
            }
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
        let markdownPayload = normalizedMarkdown.jsonStringLiteral

        let localMathJaxURL = MathMarkdownResourceResolver.mathJaxScriptURL(in: .main)
        let mathJaxLoadPlan = MathJaxLoadPlanner.plan(
            mathRenderingEnabled: mathRenderingEnabled,
            localScriptURL: localMathJaxURL
        ) { message in
            DiagnosticsLogger.log(message, level: .warning, category: .chat)
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
            mathJaxScriptTag: mathJaxLoadPlan.scriptTag,
            copyButtonLabel: L10n.text("コピー"),
            copiedButtonLabel: L10n.text("コピー済み")
        )

        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            measuredHeight = 44
            let resourceDirectory = mathJaxLoadPlan.baseURL == nil
                ? nil
                : MathMarkdownWebResourceLoader.preparedResourceDirectory()
            YamabikoWebKitSupport.loadHTMLDocument(
                html,
                resourceDirectory: resourceDirectory,
                in: webView
            )
        } else {
            context.coordinator.requestHeightMeasurement(for: webView)
        }
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
