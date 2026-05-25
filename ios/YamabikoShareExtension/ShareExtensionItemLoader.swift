import Foundation
import UniformTypeIdentifiers

enum ShareExtensionItemLoader {
    static func loadIncomingText(from extensionContext: NSExtensionContext?) async -> String {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return "" }

        var chunks: [String] = []
        for item in items {
            for provider in item.attachments ?? [] {
                if let text = await loadTextIfAvailable(from: provider) {
                    chunks.append(text)
                } else if let url = await loadURLIfAvailable(from: provider) {
                    chunks.append(url.absoluteString)
                }
            }
        }

        return chunks.joined(separator: "\n")
    }

    private static func loadTextIfAvailable(from provider: NSItemProvider) async -> String? {
        let identifiers = [
            UTType.plainText.identifier,
            UTType.text.identifier,
        ]
        for identifier in identifiers where provider.hasItemConformingToTypeIdentifier(identifier) {
            if let text = await loadText(from: provider, typeIdentifier: identifier), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    private static func loadURLIfAvailable(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return nil }
        return await loadURL(from: provider)
    }

    private static func loadText(from provider: NSItemProvider, typeIdentifier: String) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, _ in
                if let text = item as? String {
                    continuation.resume(returning: text)
                } else if let attributed = item as? NSAttributedString {
                    continuation.resume(returning: attributed.string)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                if let url = item as? URL {
                    continuation.resume(returning: url)
                } else if let text = item as? String {
                    continuation.resume(returning: URL(string: text))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
