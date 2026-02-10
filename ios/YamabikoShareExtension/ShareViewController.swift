import Social
import UniformTypeIdentifiers

final class ShareViewController: SLComposeServiceViewController {
    override func isContentValid() -> Bool {
        let typed = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !typed.isEmpty || hasIncomingItems
    }

    override func didSelectPost() {
        Task {
            let typed = contentText.trimmingCharacters(in: .whitespacesAndNewlines)
            let loaded = await loadIncomingText()
            let merged = [typed, loaded]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")

            guard !merged.isEmpty else {
                extensionContext?.completeRequest(returningItems: nil)
                return
            }

            SharePayloadPersister.save(text: merged, sourceApp: nil)
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    override func configurationItems() -> [Any]! {
        []
    }

    private var hasIncomingItems: Bool {
        (extensionContext?.inputItems as? [NSExtensionItem])?.contains(where: { item in
            (item.attachments ?? []).contains { provider in
                provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) ||
                    provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
            }
        }) ?? false
    }

    private func loadIncomingText() async -> String {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return "" }

        var chunks: [String] = []
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
                    if let text = await loadText(from: provider), !text.isEmpty {
                        chunks.append(text)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await loadURL(from: provider) {
                        chunks.append(url.absoluteString)
                    }
                }
            }
        }

        return chunks.joined(separator: "\n")
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
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

    private func loadURL(from provider: NSItemProvider) async -> URL? {
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
