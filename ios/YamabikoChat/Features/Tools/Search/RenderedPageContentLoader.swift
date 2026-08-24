import Foundation
import WebKit

struct RenderedPageContent: Sendable, Equatable {
    let title: String?
    let finalURL: URL
    let paragraphs: [PageParagraph]
}

enum RenderedPageLoadResult: Sendable, Equatable {
    case loaded(RenderedPageContent)
    case accessRestricted(reason: String)
}

protocol RenderedPageContentLoading: Sendable {
    @MainActor
    func load(html: String, sourceURL: URL, timeout: TimeInterval) async throws -> RenderedPageLoadResult
}

enum WebFetchPermitKind: Sendable {
    case http
    case webKit
}

protocol WebFetchConcurrencyLimiting: Sendable {
    func acquire(_ kind: WebFetchPermitKind) async throws
    func release(_ kind: WebFetchPermitKind) async
}

actor WebFetchConcurrencyLimiter: WebFetchConcurrencyLimiting {
    static let shared = WebFetchConcurrencyLimiter()

    private let httpLimit: Int
    private let webKitLimit: Int
    private var activeHTTP = 0
    private var activeWebKit = 0

    init(httpLimit: Int = 3, webKitLimit: Int = 1) {
        self.httpLimit = max(1, httpLimit)
        self.webKitLimit = max(1, webKitLimit)
    }

    func acquire(_ kind: WebFetchPermitKind) async throws {
        while isAtLimit(kind) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(50))
        }
        switch kind {
        case .http:
            activeHTTP += 1
        case .webKit:
            activeWebKit += 1
        }
    }

    func release(_ kind: WebFetchPermitKind) {
        switch kind {
        case .http:
            activeHTTP = max(0, activeHTTP - 1)
        case .webKit:
            activeWebKit = max(0, activeWebKit - 1)
        }
    }

    private func isAtLimit(_ kind: WebFetchPermitKind) -> Bool {
        switch kind {
        case .http:
            activeHTTP >= httpLimit
        case .webKit:
            activeWebKit >= webKitLimit
        }
    }
}

enum RenderedPageLoaderError: LocalizedError, Equatable {
    case navigationFailed(String)
    case timedOut
    case invalidExtraction

    var errorDescription: String? {
        switch self {
        case let .navigationFailed(message):
            return "Web page rendering failed: \(message)"
        case .timedOut:
            return "Web page rendering timed out"
        case .invalidExtraction:
            return "Rendered page did not return readable content"
        }
    }
}

final class WKRenderedPageContentLoader: RenderedPageContentLoading, @unchecked Sendable {
    static let shared = WKRenderedPageContentLoader()
    @MainActor
    static var extractionJavaScriptForTesting: String {
        WKRenderedPageSession.extractionJavaScript
    }

    @MainActor
    func load(html: String, sourceURL: URL, timeout: TimeInterval) async throws -> RenderedPageLoadResult {
        let session = WKRenderedPageSession(html: html, sourceURL: sourceURL, timeout: timeout)
        return try await withTaskCancellationHandler {
            try await session.start()
        } onCancel: {
            Task { @MainActor in
                session.cancel()
            }
        }
    }
}

@MainActor
private final class WKRenderedPageSession: NSObject, WKNavigationDelegate {
    private let html: String
    private let sourceURL: URL
    private let timeout: TimeInterval
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<RenderedPageLoadResult, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var extractionTask: Task<Void, Never>?
    private var completed = false

    init(html: String, sourceURL: URL, timeout: TimeInterval) {
        self.html = html
        self.sourceURL = sourceURL
        self.timeout = timeout
    }

    func start() async throws -> RenderedPageLoadResult {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let configuration = YamabikoWebKitSupport.makeConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.defaultWebpagePreferences.allowsContentJavaScript = false
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            configuration.mediaTypesRequiringUserActionForPlayback = .all

            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            self.webView = webView

            let policy = "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:; connect-src 'none'; media-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"
            let isolatedHTML = "<meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\">" + html
            webView.loadHTMLString(isolatedHTML, baseURL: nil)

            timeoutTask = Task { [weak self] in
                guard let self else { return }
                let nanoseconds = UInt64(max(1, self.timeout) * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !Task.isCancelled else { return }
                self.finish(.failure(RenderedPageLoaderError.timedOut))
            }
        }
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .other,
           navigationAction.targetFrame?.isMainFrame != false,
           navigationAction.request.url?.scheme == "about" {
            decisionHandler(.allow)
            return
        }
        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        guard navigationResponse.isForMainFrame,
              let response = navigationResponse.response as? HTTPURLResponse
        else {
            decisionHandler(.allow)
            return
        }
        guard (200 ... 299).contains(response.statusCode) else {
            decisionHandler(.cancel)
            finish(.failure(RenderedPageLoaderError.navigationFailed("HTTP \(response.statusCode)")))
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        guard extractionTask == nil else { return }
        extractionTask = Task { [weak self, weak webView] in
            guard let self, let webView else { return }
            do {
                let result = try await extractStableContent(from: webView)
                finish(.success(result))
            } catch is CancellationError {
                finish(.failure(CancellationError()))
            } catch {
                finish(.failure(error))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        finish(.failure(RenderedPageLoaderError.navigationFailed(error.localizedDescription)))
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation _: WKNavigation!,
        withError error: Error
    ) {
        finish(.failure(RenderedPageLoaderError.navigationFailed(error.localizedDescription)))
    }

    private func extractStableContent(from webView: WKWebView) async throws -> RenderedPageLoadResult {
        try await Task.sleep(for: .milliseconds(800))
        var previousSignature: String?
        var stableReadCount = 0
        let deadline = Date().addingTimeInterval(min(6, max(1, timeout - 1)))
        var latest: DOMExtractionPayload?

        while Date() < deadline {
            try Task.checkCancellation()
            let payload = try await extractDOM(from: webView)
            latest = payload

            if let restriction = payload.restriction?.trimmedNonEmpty {
                return .accessRestricted(reason: restriction)
            }
            if payload.signature == previousSignature, !payload.paragraphs.isEmpty {
                stableReadCount += 1
                if stableReadCount >= 2 {
                    return try makeLoadedResult(payload)
                }
            } else {
                stableReadCount = 0
                previousSignature = payload.signature
            }
            try await Task.sleep(for: .milliseconds(400))
        }

        guard let latest else {
            throw RenderedPageLoaderError.invalidExtraction
        }
        if let restriction = latest.restriction?.trimmedNonEmpty {
            return .accessRestricted(reason: restriction)
        }
        return try makeLoadedResult(latest)
    }

    private func extractDOM(from webView: WKWebView) async throws -> DOMExtractionPayload {
        let value = try await webView.evaluateJavaScript(Self.extractionJavaScript)
        guard let json = value as? String,
              let data = json.data(using: .utf8),
              let payload = try? JSONDecoder().decode(DOMExtractionPayload.self, from: data)
        else {
            throw RenderedPageLoaderError.invalidExtraction
        }
        return payload
    }

    private func makeLoadedResult(_ payload: DOMExtractionPayload) throws -> RenderedPageLoadResult {
        let finalURL = sourceURL
        let paragraphs = payload.paragraphs.enumerated().compactMap { offset, item -> PageParagraph? in
            guard let text = item.text.trimmedNonEmpty else { return nil }
            return PageParagraph(
                index: offset,
                heading: item.heading?.trimmedNonEmpty,
                text: text
            )
        }
        return .loaded(RenderedPageContent(
            title: payload.title?.trimmedNonEmpty,
            finalURL: finalURL,
            paragraphs: paragraphs
        ))
    }

    private func finish(_ result: Result<RenderedPageLoadResult, Error>) {
        guard !completed else { return }
        completed = true
        timeoutTask?.cancel()
        timeoutTask = nil
        extractionTask?.cancel()
        extractionTask = nil
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        let continuation = continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }

    private struct DOMExtractionPayload: Decodable {
        struct Paragraph: Decodable {
            let heading: String?
            let text: String
        }

        let title: String?
        let url: String
        let restriction: String?
        let signature: String
        let paragraphs: [Paragraph]
    }

    fileprivate static let extractionJavaScript = #"""
    (() => {
      const normalize = value => (value || '').replace(/\s+/g, ' ').trim();
      const pageText = normalize(document.body?.innerText || '');
      const lowerTitle = normalize(document.title).toLowerCase();
      const lowerStart = pageText.slice(0, 4000).toLowerCase();
      const hasPassword = !!document.querySelector('input[type="password"]');
      const captcha = /captcha|verify you are human|are you a robot|cloudflare challenge|セキュリティチェック|ロボットではない/.test(lowerTitle + ' ' + lowerStart);
      const denied = /access denied|request blocked|forbidden|アクセスが拒否|閲覧できません/.test(lowerTitle + ' ' + lowerStart) && pageText.length < 5000;
      const login = hasPassword && /sign in|log in|login|ログイン|サインイン/.test(lowerTitle + ' ' + lowerStart) && pageText.length < 5000;
      let restriction = null;
      if (captcha) restriction = 'captcha';
      else if (login) restriction = 'login_required';
      else if (denied) restriction = 'access_denied';

      const clone = document.documentElement.cloneNode(true);
      const removals = [
        'script', 'style', 'noscript', 'template', 'svg', 'canvas', 'iframe',
        'nav', 'header', 'footer', 'aside', 'form', 'dialog',
        '[hidden]', '[aria-hidden="true"]',
        '[role="navigation"]', '[role="banner"]', '[role="contentinfo"]',
        '[role="complementary"]', '[role="dialog"]', '[role="advertisement"]',
        '.advertisement', '.advert', '.ads', '.ad-container', '.ad-wrapper',
        '.cookie-banner', '.cookie-consent', '.newsletter', '.modal',
        '.navigation', '.navbar', '.sidebar', '.site-footer', '.site-header',
        '#cookie-banner', '#cookie-consent', '#sidebar', '#footer', '#header'
      ];
      clone.querySelectorAll(removals.join(',')).forEach(node => node.remove());
      clone.querySelectorAll('[style]').forEach(node => {
        const style = (node.getAttribute('style') || '').toLowerCase();
        if (/display\s*:\s*none|visibility\s*:\s*hidden/.test(style)) node.remove();
      });

      const candidates = Array.from(clone.querySelectorAll('article, main, [role="main"]'));
      let root = candidates.sort((a, b) => normalize(b.innerText || b.textContent).length - normalize(a.innerText || a.textContent).length)[0] || clone.querySelector('body') || clone;
      let heading = null;
      const paragraphs = [];
      let previousText = null;
      root.querySelectorAll('h1, h2, h3, p, li, blockquote, pre, td, th').forEach(node => {
        const text = normalize(node.innerText || node.textContent);
        if (!text) return;
        if (/^H[1-3]$/.test(node.tagName)) {
          heading = text;
          return;
        }
        if (text === previousText) return;
        paragraphs.push({ heading, text });
        previousText = text;
      });
      if (!paragraphs.length) {
        const text = normalize(root.innerText || root.textContent);
        if (text) paragraphs.push({ heading: null, text });
      }
      const combined = paragraphs.map(item => item.text).join('\n');
      return JSON.stringify({
        title: normalize(document.title) || null,
        url: document.location.href,
        restriction,
        signature: `${paragraphs.length}:${combined.length}:${combined.slice(-200)}`,
        paragraphs
      });
    })();
    """#
}
