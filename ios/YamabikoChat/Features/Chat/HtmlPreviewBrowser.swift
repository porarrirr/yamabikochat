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
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.pageTitle = $pageTitle
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.navigationDelegate = nil
        webView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var pageTitle: Binding<String>

        init(pageTitle: Binding<String>) {
            self.pageTitle = pageTitle
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
            switch scheme {
            case "about", "data", "http", "https":
                decisionHandler(.allow)
            default:
                decisionHandler(.cancel)
            }
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
