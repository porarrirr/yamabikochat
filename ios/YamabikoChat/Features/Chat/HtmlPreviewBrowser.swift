import SwiftUI
import WebKit

struct HtmlPreviewBrowser: View {
    let html: String
    let filename: String

    @Environment(\.dismiss) private var dismiss
    @State private var pageTitle: String = ""

    var body: some View {
        NavigationStack {
            HtmlPreviewWebView(html: html, pageTitle: $pageTitle)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(displayedTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(L10n.text("閉じる"))
                    }
                }
        }
        .presentationDragIndicator(.visible)
    }

    private var displayedTitle: String {
        if !pageTitle.isEmpty {
            return pageTitle
        }
        return HtmlCodeExtractor.documentTitle(from: html) ?? filename
    }
}

struct HtmlPreviewWebView: UIViewRepresentable {
    let html: String
    @Binding var pageTitle: String

    func makeCoordinator() -> Coordinator {
        Coordinator(pageTitle: $pageTitle)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = YamabikoWebKitSupport.makeConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.load(html: html, in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.pageTitle = $pageTitle
        context.coordinator.load(html: html, in: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var pageTitle: Binding<String>
        private var loadedHTML: String?

        init(pageTitle: Binding<String>) {
            self.pageTitle = pageTitle
        }

        func load(html: String, in webView: WKWebView) {
            guard loadedHTML != html else { return }
            loadedHTML = html
            pageTitle.wrappedValue = ""
            webView.loadHTMLString(Self.sandbox(html), baseURL: nil)
        }

        static func sandbox(_ html: String) -> String {
            let policy = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; media-src data: blob:; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'\">"
            if let head = html.range(of: "<head", options: [.caseInsensitive])?.lowerBound,
               let end = html[head...].firstIndex(of: ">") {
                var result = html
                result.insert(contentsOf: policy, at: result.index(after: end))
                return result
            }
            return policy + html
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .other,
               let scheme = navigationAction.request.url?.scheme?.lowercased(),
               scheme == "about" || scheme == "data" {
                decisionHandler(.allow)
                return
            }
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url,
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                UIApplication.shared.open(url)
            }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            webView.evaluateJavaScript("document.title") { [pageTitle] result, _ in
                if let title = result as? String {
                    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        DispatchQueue.main.async {
                            pageTitle.wrappedValue = trimmed
                        }
                    }
                }
            }
        }
    }
}
