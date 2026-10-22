import Foundation
import WebKit

enum YamabikoWebKitSupport {
    static func makeConfiguration(userContentController: WKUserContentController? = nil) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
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
            try synchronizeResources(
                from: sourceDirectory,
                to: cacheDirectory,
                fileManager: fileManager
            )
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

    /// Caches can survive an app update and can be purged at any time. Keep the
    /// copy identical to the bundle instead of trusting an existing filename.
    static func synchronizeResources(
        from sourceDirectory: URL,
        to destinationDirectory: URL,
        fileManager: FileManager = .default
    ) throws {
        let resourceNames = try fileManager.contentsOfDirectory(atPath: sourceDirectory.path)
        for resourceName in resourceNames {
            let sourceURL = sourceDirectory.appendingPathComponent(resourceName)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue
            else { continue }

            let destinationURL = destinationDirectory.appendingPathComponent(resourceName)
            guard needsCopy(
                from: sourceURL,
                to: destinationURL,
                fileManager: fileManager
            ) else { continue }

            let temporaryURL = destinationDirectory
                .appendingPathComponent(".\(resourceName).tmp", isDirectory: false)
            try? fileManager.removeItem(at: temporaryURL)
            try fileManager.copyItem(at: sourceURL, to: temporaryURL)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        }
    }

    private static func needsCopy(
        from sourceURL: URL,
        to destinationURL: URL,
        fileManager: FileManager
    ) -> Bool {
        guard fileManager.fileExists(atPath: destinationURL.path) else { return true }
        guard let sourceAttributes = try? fileManager.attributesOfItem(atPath: sourceURL.path),
              let destinationAttributes = try? fileManager.attributesOfItem(atPath: destinationURL.path),
              let sourceSize = sourceAttributes[.size] as? NSNumber,
              let destinationSize = destinationAttributes[.size] as? NSNumber
        else { return true }
        guard sourceSize == destinationSize else { return true }
        let sourceDate = sourceAttributes[.modificationDate] as? Date
        let destinationDate = destinationAttributes[.modificationDate] as? Date
        return sourceDate != destinationDate
    }
}
