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
    static func buildHTML(svgContent: String, maxHeight: CGFloat) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <style>
            html, body {
              margin: 0;
              padding: 0;
              background: transparent;
              height: 100%;
            }
            body {
              display: flex;
              align-items: center;
              justify-content: center;
              min-height: 0;
              padding: 8px;
              box-sizing: border-box;
            }
            svg {
              max-width: 100%;
              max-height: \(Int(maxHeight))px;
              width: auto;
              height: auto;
              display: block;
            }
          </style>
        </head>
        <body>
          \(svgContent)
        </body>
        </html>
        """
    }
}

struct SvgPreviewWebView: UIViewRepresentable {
    let svgContent: String
    var maxHeight: CGFloat = 260
    var onError: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = YamabikoWebKitSupport.makeConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onError = onError
        guard context.coordinator.shouldRender(svgContent: svgContent, maxHeight: maxHeight) else { return }
        let sanitized = SvgPreviewSanitizer.sanitize(svgContent)
        let html = SvgPreviewHTMLBuilder.buildHTML(svgContent: sanitized, maxHeight: maxHeight)
        guard context.coordinator.lastHTML != html else { return }

        context.coordinator.lastHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onError: ((String) -> Void)?
        var lastHTML: String?
        private var lastSVGContent: String?
        private var lastMaxHeight: CGFloat?

        init(onError: ((String) -> Void)?) {
            self.onError = onError
        }

        func shouldRender(svgContent: String, maxHeight: CGFloat) -> Bool {
            guard lastSVGContent != svgContent || lastMaxHeight != maxHeight else { return false }
            lastSVGContent = svgContent
            lastMaxHeight = maxHeight
            return true
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
            onError?(error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            onError?(error.localizedDescription)
        }
    }
}
