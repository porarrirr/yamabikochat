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

        let htmlURL = resourceDirectory.appendingPathComponent("message-\(UUID().uuidString).html")
        do {
            try html.write(to: htmlURL, atomically: true, encoding: .utf8)
            webView.loadFileURL(htmlURL, allowingReadAccessTo: resourceDirectory)
            return true
        } catch {
            webView.loadHTMLString(html, baseURL: resourceDirectory)
            return false
        }
    }
}

enum MathMarkdownWebResourceLoader {
    private static let cacheDirectoryName = "yamabiko-math-web"

    static func preparedResourceDirectory(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> URL? {
        guard
            let sourceDirectory = MathMarkdownResourceResolver.mathJaxScriptURL(in: bundle)?
                .deletingLastPathComponent(),
            let cacheRoot = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
        else {
            return nil
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
            return nil
        }
    }
}
