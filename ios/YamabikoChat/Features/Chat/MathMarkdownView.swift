import SwiftUI
import WebKit
import UIKit
import Foundation
import CryptoKit

enum MathMarkdownNormalizer {
    private static let completeMathRegex = try! NSRegularExpression(
        pattern: #"(?<!\\)(?:\\{1,2}\[[\s\S]*?\\{1,2}\]|\\{1,2}\([\s\S]*?\\{1,2}\)|\$\$[\s\S]*?\$\$|(?<!\$)\$(?!\$)[^\n$]+?(?<!\\)\$(?![A-Za-z0-9]))"#
    )

    static func normalizeEscapedMathIfNeeded(_ markdown: String) -> String {
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
        // Inside TeX, \\n is a row break followed by n, and \\[2pt]
        // sets row spacing. Decode transport escapes only outside equations;
        // only the outer math delimiters may need unescaping.
        var output = ""
        var cursor = text.startIndex
        let matches = completeMathRegex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            output += normalizeTransportEscapes(String(text[cursor..<range.lowerBound]))
            var equation = String(text[range])
            for (escaped, delimiter) in [(#"\\("#, #"\("#), (#"\\["#, #"\["#)] where equation.hasPrefix(escaped) {
                equation.replaceSubrange(equation.startIndex..<equation.index(equation.startIndex, offsetBy: escaped.count), with: delimiter)
            }
            for (escaped, delimiter) in [(#"\\)"#, #"\)"#), (#"\\]"#, #"\]"#)] where equation.hasSuffix(escaped) {
                equation.replaceSubrange(equation.index(equation.endIndex, offsetBy: -escaped.count)..<equation.endIndex, with: delimiter)
            }
            output += equation
            cursor = range.upperBound
        }
        output += normalizeTransportEscapes(String(text[cursor...]))
        return output
    }

    private static func normalizeTransportEscapes(_ text: String) -> String {
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

    static func transformOutsideCode(_ markdown: String, transform: (String) -> String) -> String {
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
        mathJaxScriptTag: String,
        copyButtonLabel: String = "コピー",
        copiedButtonLabel: String = "コピー済み"
    ) -> String {
        let copyLabelSetupScript = """
          <script>
            window.__yamabikoCopyButtonLabel = \(copyButtonLabel.jsonStringLiteral);
            window.__yamabikoCopiedButtonLabel = \(copiedButtonLabel.jsonStringLiteral);
          </script>
        """
        let mathSetupScript = """
          <script>
            window.__yamabikoMathJaxLoadFailed = \(mathJaxScriptTag.isEmpty ? "true" : "false");
            // A single document owns one startup. Every render waits for this
            // promise instead of guessing from script-load timing.
            window.__yamabikoMathJaxReady = new Promise(function(resolve, reject) {
              var settled = false;
              function complete() {
                if (settled) return;
                settled = true;
                resolve();
              }
              function fail(reason) {
                if (settled) return;
                settled = true;
                reject(reason);
              }
              window.__yamabikoMathJaxReadyResolve = complete;
              window.__yamabikoMathJaxReadyReject = fail;
              setTimeout(function() { fail(new Error('MathJax startup timed out')); }, 8000);
              var deadline = Date.now() + 8000;
              function check() {
                if (settled) return;
                var math = window.MathJax;
                if (math && math.startup && math.startup.promise &&
                    typeof math.startup.promise.then === 'function') {
                  math.startup.promise.then(complete, fail);
                  return;
                }
                if (math && typeof math.typesetPromise === 'function') {
                  complete();
                  return;
                }
                if (window.__yamabikoMathJaxLoadFailed) {
                  fail(new Error('MathJax failed to load'));
                  return;
                }
                if (Date.now() > deadline) {
                  fail(new Error('MathJax did not start'));
                  return;
                }
                setTimeout(check, 10);
              }
              check();
            });
            window.MathJax = {
              tex: {
                inlineMath: [['$', '$'], ['\\\\(', '\\\\)']],
                displayMath: [['$$', '$$'], ['\\\\[', '\\\\]']],
                processEscapes: true,
                processEnvironments: true,
                packages: {'[-]': ['require']}
              },
              startup: { typeset: false },
              svg: { fontCache: 'global' },
              options: { enableMenu: false }
            };
            window.__yamabikoMathJaxOnError = function() {
              window.__yamabikoMathJaxLoadFailed = true;
              if (window.console && window.console.warn) {
                window.console.warn('MathJax script failed to load.');
              }
              if (window.__yamabikoMathJaxReadyReject) {
                window.__yamabikoMathJaxReadyReject(new Error('MathJax failed to load'));
              }
              if (window.__yamabikoSendHeight) window.__yamabikoSendHeight();
            };
          </script>
          \(mathJaxScriptTag)
        """
        let mathTypesetScript = """
              // Waiting for MathJax's own startup promise avoids treating raw
              // TeX as a finished render while the engine is still loading.
              return window.__yamabikoMathJaxReady.then(function() {
                var math = window.MathJax;
                if (!math || typeof math.typesetPromise !== 'function') {
                  throw new Error('MathJax is unavailable');
                }
                return math.typesetPromise([root]);
              }).then(finish);
        """

        return """
        <html>
        <head>
          <meta charset=\"utf-8\" />
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
          <meta name=\"color-scheme\" content=\"light dark\" />
          <meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'self' 'unsafe-inline' file:; style-src 'unsafe-inline'; img-src data:; font-src 'self' file: data:; connect-src 'none'; media-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'\" />
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
            .yamabiko-markdown {
              /* Include display-math margins in the height reported to SwiftUI. */
              display: flow-root;
              max-width: 100%;
            }
            .yamabiko-markdown > :first-child { margin-top: 0; }
            .yamabiko-markdown > :last-child { margin-bottom: 0; }
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
          <div id=\"yamabiko-markdown\" class=\"yamabiko-markdown\"></div>
          <script>
            (function() {
              var source = \(markdownPayload);
              var root = document.getElementById('yamabiko-markdown');
              if (!root) return;
              var copyLabel = window.__yamabikoCopyButtonLabel || 'Copy';
              var copiedLabel = window.__yamabikoCopiedButtonLabel || 'Copied';
              var renderGeneration = 0;
              var renderQueue = Promise.resolve();
              window.__yamabikoContentReady = false;
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
              window.__yamabikoRenderSource = function(nextSource, shouldTypeset) {
                renderGeneration += 1;
                var generation = renderGeneration;
                source = String(nextSource || '');
                var renderSource = source;
                // Keep the committed DOM visible while MathJax works. Serialize
                // jobs because MathJax shares document state between renders.
                renderQueue = renderQueue.then(function() {
                  if (generation !== renderGeneration) return;
                  var staging = document.createElement('div');
                  staging.className = 'yamabiko-markdown';
                  staging.style.cssText = 'position:absolute;visibility:hidden;pointer-events:none;top:0;left:0;';
                  staging.style.width = root.getBoundingClientRect().width + 'px';
                  if (typeof window.yamabikoRenderMarkdown === 'function') {
                    staging.innerHTML = window.yamabikoRenderMarkdown(renderSource);
                  } else {
                    staging.textContent = renderSource;
                  }
                  document.body.appendChild(staging);
                  return new Promise(function(resolve, reject) {
                    function finishRender() {
                      if (generation === renderGeneration) {
                        if (window.MathJax && window.MathJax.typesetClear) {
                          try { window.MathJax.typesetClear([root]); } catch (_) {}
                        }
                        root.replaceChildren.apply(root, Array.from(staging.childNodes));
                        window.__yamabikoContentReady = renderSource.length > 0;
                        enableHorizontalScrollContainers();
                      } else if (window.MathJax && window.MathJax.typesetClear) {
                        try { window.MathJax.typesetClear([staging]); } catch (_) {}
                      }
                      staging.remove();
                      if (window.__yamabikoSendHeight) window.__yamabikoSendHeight();
                      resolve();
                    }
                    if (shouldTypeset) {
                      typesetRenderedContent(staging, finishRender).catch(function(error) {
                        if (window.MathJax && window.MathJax.typesetClear) {
                          try { window.MathJax.typesetClear([staging]); } catch (_) {}
                        }
                        staging.remove();
                        reject(error);
                      });
                    } else {
                      finishRender();
                    }
                  });
                }).catch(function(error) {
                  // Recover the queue so later content updates can still render.
                  // Failed typesetting must never publish raw TeX as success.
                  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.mathRenderError) {
                    window.webkit.messageHandlers.mathRenderError.postMessage(String(error && error.message || error));
                  }
                });
              };
              window.__yamabikoRenderSource(source, true);
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
        localScriptURL: URL?,
        logger: (String) -> Void = { _ in }
    ) -> MathJaxLoadPlan {
        let onErrorHandler = "window.__yamabikoMathJaxOnError && window.__yamabikoMathJaxOnError();"
        if let localScriptURL {
            return MathJaxLoadPlan(
                scriptTag: "<script src=\"tex-svg.js\" onerror=\"\(onErrorHandler)\"></script>",
                baseURL: localScriptURL.deletingLastPathComponent()
            )
        }

        logger("MathJax local script missing; cannot render math for this message.")
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
          var heightFrame = 0;
          var heightTimer = 0;
          var lastPostedHeight = -1;
          function sendHeight() {
            if (window.__yamabikoEnableHorizontalScroll) {
              window.__yamabikoEnableHorizontalScroll();
            }
            var body = document.body;
            var root = document.getElementById('yamabiko-markdown');
            if (!body || !root || !window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.\(messageName)) {
              return;
            }
            if (!window.__yamabikoContentReady) return;
            var rect = root.getBoundingClientRect();
            var height = Math.max(
              root.scrollHeight || 0,
              root.offsetHeight || 0,
              rect && isFinite(rect.height) ? rect.height : 0
            );
            if (!isFinite(height) || height <= 0) {
              height = Math.max(body.scrollHeight || 0, body.offsetHeight || 0);
            }
            var roundedHeight = Math.ceil(height);
            if (roundedHeight === lastPostedHeight) return;
            lastPostedHeight = roundedHeight;
            window.webkit.messageHandlers.\(messageName).postMessage(roundedHeight);
          }
          function scheduleHeight() {
            // A hidden or recycled cell can suspend requestAnimationFrame.
            // Keep a timer fallback so a rendered math block still reports its
            // height when the cell comes back on screen.
            if (!heightTimer) {
              heightTimer = setTimeout(function() {
                heightTimer = 0;
                sendHeight();
              }, 50);
            }
            if (heightFrame) return;
            heightFrame = requestAnimationFrame(function() {
              heightFrame = 0;
              sendHeight();
            });
          }
          window.__yamabikoSendHeight = scheduleHeight;
          window.addEventListener('load', function() {
            scheduleHeight();
            setTimeout(scheduleHeight, 80);
            setTimeout(scheduleHeight, 220);
            setTimeout(scheduleHeight, 420);
          });
          window.addEventListener('resize', scheduleHeight);
          if (window.ResizeObserver) {
            var observer = new ResizeObserver(function() { scheduleHeight(); });
            var observedRoot = document.getElementById('yamabiko-markdown');
            if (observedRoot) observer.observe(observedRoot);
          }
          if (window.MutationObserver) {
            var mutationRoot = document.getElementById('yamabiko-markdown');
            if (mutationRoot) {
              var mutationObserver = new MutationObserver(function() { scheduleHeight(); });
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
    var isStreaming: Bool = false
    var onLayoutChange: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var contentHeight: CGFloat = minimumHeight
    @State private var hasRenderedContent = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !hasRenderedContent {
                NativeMarkdownMathPlaceholder(markdownText: markdownText)
            }
            MathMarkdownWebView(
                markdownText: markdownText,
                isStreaming: isStreaming,
                colorScheme: colorScheme,
                measuredHeight: $contentHeight,
                hasRenderedContent: $hasRenderedContent
            )
            .frame(height: max(Self.minimumHeight, contentHeight))
            .opacity(hasRenderedContent ? 1 : 0)
            .allowsHitTesting(hasRenderedContent)
            .accessibilityHidden(!hasRenderedContent)
        }
        .onChange(of: contentHeight) { _, _ in
            onLayoutChange?()
        }
        .onChange(of: hasRenderedContent) { _, _ in
            // Removing the placeholder can change the row's height even when
            // WebKit's measured height has not changed.
            onLayoutChange?()
        }
        .transaction { $0.animation = nil }
        .onChange(of: colorScheme) { _, _ in
            hasRenderedContent = false
        }
    }
}

struct MathMarkdownInputSignature: Equatable {
    let markdownText: String
    let isStreaming: Bool
    let colorScheme: ColorScheme
}

struct MathMarkdownDocumentSignature: Equatable {
    let colorScheme: ColorScheme
    let mathJaxScriptTag: String
    let copyButtonLabel: String
    let copiedButtonLabel: String

    fileprivate var cacheKey: NSString {
        [
            colorScheme == .dark ? "dark" : "light",
            mathJaxScriptTag,
            copyButtonLabel,
            copiedButtonLabel
        ].joined(separator: "\u{1F}") as NSString
    }
}

enum MathMarkdownDocumentCache {
    private static let storage: NSCache<NSString, NSString> = {
        let cache = NSCache<NSString, NSString>()
        cache.countLimit = 8
        return cache
    }()

    static func document(
        for signature: MathMarkdownDocumentSignature,
        build: () -> String
    ) -> String {
        if let cached = storage.object(forKey: signature.cacheKey) {
            return cached as String
        }
        let value = build()
        storage.setObject(value as NSString, forKey: signature.cacheKey)
        return value
    }
}

enum MathMarkdownDocumentFileStore {
    /// `loadHTMLString` does not reliably grant a file base URL access to its
    /// sibling MathJax script on every OS. A real document loaded with
    /// `loadFileURL(_:allowingReadAccessTo:)` gives the renderer the same
    /// subresource contract that Mermaid already uses.
    static func documentURL(for html: String, in directory: URL) throws -> URL {
        let digest = SHA256.hash(data: Data(html.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let url = directory.appendingPathComponent("math-document-\(digest).html")
        if let existing = try? String(contentsOf: url, encoding: .utf8),
           existing == html {
            return url
        }
        try html.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

private final class MathMarkdownWKWebView: WKWebView {
    var onViewportLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onViewportLayout?()
    }
}

private struct MathMarkdownWebView: UIViewRepresentable {
    let markdownText: String
    let isStreaming: Bool
    let colorScheme: ColorScheme
    @Binding var measuredHeight: CGFloat
    @Binding var hasRenderedContent: Bool
    private static let markdownRendererScript: String = {
        MathMarkdownResourceResolver.markdownRendererScript(
            in: .main,
            fallbackScript: MathMarkdownRendererSource.script
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
        contentController.add(context.coordinator, name: Coordinator.errorMessageName)

        let userScript = WKUserScript(
            source: MathMarkdownHeightScript.source(messageName: Coordinator.heightMessageName),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(userScript)

        let config = YamabikoWebKitSupport.makeConfiguration(userContentController: contentController)

        let webView = MathMarkdownWKWebView(frame: .zero, configuration: config)
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

        let inputSignature = MathMarkdownInputSignature(
            markdownText: markdownText,
            isStreaming: isStreaming,
            colorScheme: colorScheme
        )
        guard context.coordinator.beginUpdate(inputSignature) else { return }

        let normalizedMarkdown = MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(markdownText)
        let localMathJaxURL = MathMarkdownResourceResolver.mathJaxScriptURL(in: .main)
        let mathJaxLoadPlan = MathJaxLoadPlanner.plan(
            localScriptURL: localMathJaxURL
        ) { message in
            MathMarkdownDiagnostics.logWarning(message)
        }

        let bodyTextColor = colorScheme == .dark ? "#F2F2F7" : "#1C1C1E"
        let codeBackgroundColor = colorScheme == .dark ? "#1F1F23" : "#F4F4F8"
        let borderColor = colorScheme == .dark ? "#38383A" : "#E5E5EA"
        let linkColor = colorScheme == .dark ? "#70A7FF" : "#1F64E0"

        let documentSignature = MathMarkdownDocumentSignature(
            colorScheme: colorScheme,
            mathJaxScriptTag: mathJaxLoadPlan.scriptTag,
            copyButtonLabel: L10n.text("コピー"),
            copiedButtonLabel: L10n.text("コピー済み")
        )
        let html = MathMarkdownDocumentCache.document(for: documentSignature) {
            MathMarkdownHTMLBuilder.buildHTML(
                markdownPayload: "\"\"",
                markdownRendererScript: Self.markdownRendererScript,
                bodyTextColor: bodyTextColor,
                codeBackgroundColor: codeBackgroundColor,
                borderColor: borderColor,
                linkColor: linkColor,
                mathJaxScriptTag: mathJaxLoadPlan.scriptTag,
                copyButtonLabel: documentSignature.copyButtonLabel,
                copiedButtonLabel: documentSignature.copiedButtonLabel
            )
        }

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
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.errorMessageName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let heightMessageName = "contentHeight"
        static let copyMessageName = "copyCodeBlock"
        static let errorMessageName = "mathRenderError"

        var parent: MathMarkdownWebView
        var lastHTML: String?
        private var lastInputSignature: MathMarkdownInputSignature?
        private var pendingLoadToken = 0
        private var pendingRenderToken = 0
        private var didFinishInitialLoad = false
        private var pendingMarkdownPayload: String?
        private var pendingIsStreaming = false
        private var lastRenderedMarkdownPayload: String?
        private var lastRenderWasStreaming = false
        private var pendingRevealToken = 0

        init(parent: MathMarkdownWebView) {
            self.parent = parent
        }

        func beginUpdate(_ signature: MathMarkdownInputSignature) -> Bool {
            guard lastInputSignature != signature else { return false }
            lastInputSignature = signature
            return true
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
            if navigationAction.navigationType == .other,
               navigationAction.targetFrame?.isMainFrame == true,
               navigationAction.request.url?.scheme == "file" {
                decisionHandler(.allow)
                return
            }
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
            decisionHandler(.cancel)
        }

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == Self.errorMessageName {
                MathMarkdownDiagnostics.logWarning("MathMarkdown rendering failed: \(message.body)")
                return
            }
            if message.name == Self.copyMessageName {
                if let codeText = message.body as? String {
                    UIPasteboard.general.string = codeText
                }
                return
            }

            guard message.name == Self.heightMessageName else { return }
            if let value = message.body as? NSNumber {
                apply(height: CGFloat(truncating: value), in: message.webView)
            } else if let value = message.body as? Double {
                apply(height: CGFloat(value), in: message.webView)
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
            pendingRevealToken += 1
            let documentURL = resourceDirectory.flatMap {
                try? MathMarkdownDocumentFileStore.documentURL(for: html, in: $0)
            }
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView, token == self.pendingLoadToken, self.lastHTML == html else {
                    return
                }
                if let documentURL, let resourceDirectory {
                    webView.loadFileURL(
                        documentURL,
                        allowingReadAccessTo: resourceDirectory
                    )
                } else {
                    YamabikoWebKitSupport.loadHTMLDocument(
                        html,
                        resourceDirectory: resourceDirectory,
                        in: webView
                    )
                }
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
            guard force || lastRenderedMarkdownPayload != markdownPayload else { return }

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

                let shouldTypeset = isStreaming ? "false" : "true"
                let script = "window.__yamabikoRenderSource && window.__yamabikoRenderSource(\(markdownPayload), \(shouldTypeset));"
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

        private func apply(height rawHeight: CGFloat, in webView: WKWebView?) {
            guard rawHeight.isFinite, rawHeight > 0 else { return }
            let clamped = max(44, rawHeight.rounded(.up))
            let loadToken = pendingLoadToken
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, loadToken == self.pendingLoadToken else { return }
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    if abs(self.parent.measuredHeight - clamped) > 1 {
                        self.parent.measuredHeight = clamped
                    }
                }
                guard !self.parent.hasRenderedContent, let webView else { return }
                self.pendingRevealToken += 1
                let revealToken = self.pendingRevealToken
                // First let SwiftUI apply the measured viewport. A DOM height
                // message alone says nothing about WebKit's composited pixels.
                // A snapshot waits for those pixels before we remove the text.
                guard let webView = webView as? MathMarkdownWKWebView else { return }
                var snapshotInFlight = false
                webView.onViewportLayout = { [weak self, weak webView] in
                    guard let self, let webView,
                          revealToken == self.pendingRevealToken,
                          loadToken == self.pendingLoadToken,
                          !snapshotInFlight,
                          webView.bounds.width > 0,
                          webView.bounds.height >= clamped - 1 else { return }
                    snapshotInFlight = true
                    let configuration = WKSnapshotConfiguration()
                    configuration.rect = CGRect(
                        x: 0, y: 0, width: webView.bounds.width,
                        height: min(webView.bounds.height, 128)
                    )
                    webView.takeSnapshot(with: configuration) { [weak self, weak webView] image, _ in
                        snapshotInFlight = false
                        guard let self, image != nil,
                              revealToken == self.pendingRevealToken,
                              loadToken == self.pendingLoadToken else { return }
                        webView?.onViewportLayout = nil
                        var transaction = Transaction()
                        transaction.animation = nil
                        withTransaction(transaction) {
                            self.parent.hasRenderedContent = true
                        }
                    }
                }
                webView.setNeedsLayout()
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
