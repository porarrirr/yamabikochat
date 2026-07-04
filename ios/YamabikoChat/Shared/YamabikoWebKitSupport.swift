import Foundation
import WebKit

enum YamabikoWebKitSupport {
    static let sharedProcessPool = WKProcessPool()

    static func makeConfiguration(userContentController: WKUserContentController? = nil) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = sharedProcessPool
        if let userContentController {
            configuration.userContentController = userContentController
        }
        return configuration
    }

    @discardableResult
    static func loadHTMLDocument(
        _ html: String,
        resourceDirectory: URL?,
        in webView: WKWebView
    ) -> Bool {
        guard let resourceDirectory else {
            webView.loadHTMLString(html, baseURL: nil)
            return false
        }

        webView.loadHTMLString(html, baseURL: resourceDirectory)
        return true
    }
}

enum MathMarkdownWebResourceLoader {
    private static let cacheDirectoryName = "yamabiko-math-web"

    static func preparedResourceDirectory(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let sourceDirectory = MathMarkdownResourceResolver.mathJaxScriptURL(in: bundle)?
            .deletingLastPathComponent()
        else {
            DiagnosticsLogger.log(
                "MathJax resource directory not found in bundle",
                category: .app
            )
            return nil
        }

        guard let cacheRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            DiagnosticsLogger.log(
                "MathJax cache root unavailable; using bundle directory",
                category: .app
            )
            return sourceDirectory
        }

        let cacheDirectory = cacheRoot.appendingPathComponent(cacheDirectoryName, isDirectory: true)
        do {
            try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            let resourceNames = try fileManager.contentsOfDirectory(atPath: sourceDirectory.path)
            for resourceName in resourceNames {
                let sourceURL = sourceDirectory.appendingPathComponent(resourceName)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                    continue
                }

                let destinationURL = cacheDirectory.appendingPathComponent(resourceName)
                if fileManager.fileExists(atPath: destinationURL.path) {
                    continue
                }
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
            }
            return cacheDirectory
        } catch {
            DiagnosticsLogger.log(
                "MathJax cache preparation failed; using bundle directory",
                category: .app,
                error: error
            )
            return sourceDirectory
        }
    }
}
