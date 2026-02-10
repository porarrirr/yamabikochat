import SwiftUI
import WebKit

struct MathMarkdownView: UIViewRepresentable {
    let markdownText: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
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

        let html = """
        <html>
        <head>
          <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
          \(scriptTag)
          <style>
            body { font-family: -apple-system; font-size: 15px; color: #222; margin: 0; padding: 0; }
            code, pre { font-family: Menlo, monospace; }
          </style>
        </head>
        <body>
          \(escaped)
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
