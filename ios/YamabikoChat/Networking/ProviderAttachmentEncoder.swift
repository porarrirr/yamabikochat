import Foundation
import UniformTypeIdentifiers

enum ProviderAttachmentEncoder {
    struct InlinePayload: Equatable {
        let mimeType: String
        let base64Data: String

        var dataURL: String {
            "data:\(mimeType);base64,\(base64Data)"
        }

        var isImage: Bool {
            mimeType.lowercased().hasPrefix("image/")
        }
    }

    static func shouldEmbedImages(metadata: [String: String]) -> Bool {
        metadata["supportsVision"] == "true"
    }

    static func resolveFileURL(from rawAttachment: String) -> URL? {
        if let parsed = URL(string: rawAttachment), parsed.isFileURL {
            return parsed
        }

        let directPath = URL(fileURLWithPath: rawAttachment)
        if FileManager.default.fileExists(atPath: directPath.path) {
            return directPath
        }

        if let decoded = rawAttachment.removingPercentEncoding {
            let decodedPath = URL(fileURLWithPath: decoded)
            if FileManager.default.fileExists(atPath: decodedPath.path) {
                return decodedPath
            }
        }

        return nil
    }

    static func resolveMimeType(fileURL: URL) -> String {
        if let values = try? fileURL.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = values.contentType,
           let mime = contentType.preferredMIMEType,
           !mime.isEmpty {
            return mime
        }

        let ext = fileURL.pathExtension
        if let type = UTType(filenameExtension: ext),
           let mime = type.preferredMIMEType,
           !mime.isEmpty {
            return mime
        }

        return "application/octet-stream"
    }

    static func loadInlinePayload(from rawAttachment: String) -> InlinePayload? {
        guard let fileURL = resolveFileURL(from: rawAttachment) else {
            DiagnosticsLogger.log(
                "Attachment skipped: unreadable file URL",
                category: .network,
                metadata: ["attachment_extension": URL(fileURLWithPath: rawAttachment).pathExtension]
            )
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let mime = resolveMimeType(fileURL: fileURL)
            return InlinePayload(mimeType: mime, base64Data: data.base64EncodedString())
        } catch {
            DiagnosticsLogger.log(
                "Attachment skipped: file read failed",
                category: .network,
                metadata: ["attachment_extension": fileURL.pathExtension],
                error: error
            )
            return nil
        }
    }

    static func loadImagePayloads(from attachments: [String], embedImages: Bool) -> [InlinePayload] {
        guard embedImages else { return [] }
        return attachments.compactMap { raw in
            guard let payload = loadInlinePayload(from: raw) else { return nil }
            guard payload.isImage else {
                DiagnosticsLogger.log(
                    "Attachment skipped: non-image type not embedded in vision request",
                    category: .network,
                    metadata: ["mime_type": payload.mimeType]
                )
                return nil
            }
            return payload
        }
    }

    // MARK: - Gemini

    static func geminiInlineDataPart(from rawAttachment: String, embedImages: Bool) -> [String: Any]? {
        guard embedImages else { return nil }
        guard let payload = loadInlinePayload(from: rawAttachment) else { return nil }
        return [
            "inlineData": [
                "mimeType": payload.mimeType,
                "data": payload.base64Data
            ]
        ]
    }

    static func buildGeminiParts(text: String, attachments: [String], embedImages: Bool) -> [[String: Any]] {
        var parts: [[String: Any]] = [["text": text]]
        for attachment in attachments {
            if let inline = geminiInlineDataPart(from: attachment, embedImages: embedImages) {
                parts.append(inline)
            }
        }
        return parts
    }

    // MARK: - OpenAI-compatible (chat/completions, OpenCode Go chat)

    enum OpenAIMessageContent: Encodable {
        case plain(String)
        case parts([OpenAIContentPart])

        func encode(to encoder: Encoder) throws {
            switch self {
            case let .plain(text):
                var container = encoder.singleValueContainer()
                try container.encode(text)
            case let .parts(parts):
                var container = encoder.unkeyedContainer()
                for part in parts {
                    try container.encode(part)
                }
            }
        }
    }

    struct OpenAIContentPart: Encodable {
        let type: String
        let text: String?
        let imageURL: OpenAIImageURLWrapper?

        enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }

        static func textPart(_ text: String) -> OpenAIContentPart {
            OpenAIContentPart(type: "text", text: text, imageURL: nil)
        }

        static func imagePart(dataURL: String) -> OpenAIContentPart {
            OpenAIContentPart(
                type: "image_url",
                text: nil,
                imageURL: OpenAIImageURLWrapper(url: dataURL)
            )
        }
    }

    struct OpenAIImageURLWrapper: Encodable {
        let url: String
    }

    static func buildOpenAIMessageContent(
        text: String,
        attachments: [String],
        embedImages: Bool
    ) -> OpenAIMessageContent {
        let images = loadImagePayloads(from: attachments, embedImages: embedImages)
        guard !images.isEmpty else {
            return .plain(text)
        }

        var parts: [OpenAIContentPart] = []
        if !text.isEmpty {
            parts.append(.textPart(text))
        }
        for image in images {
            parts.append(.imagePart(dataURL: image.dataURL))
        }
        if parts.isEmpty {
            return .plain(text)
        }
        return .parts(parts)
    }

    // MARK: - Anthropic-compatible (messages API, OpenCode Go messages)

    struct AnthropicContentBlock: Encodable {
        let type: String
        let text: String?
        let source: AnthropicImageSource?

        static func textBlock(_ text: String) -> AnthropicContentBlock {
            AnthropicContentBlock(type: "text", text: text, source: nil)
        }

        static func imageBlock(payload: InlinePayload) -> AnthropicContentBlock {
            AnthropicContentBlock(
                type: "image",
                text: nil,
                source: AnthropicImageSource(
                    type: "base64",
                    mediaType: payload.mimeType,
                    data: payload.base64Data
                )
            )
        }
    }

    struct AnthropicImageSource: Encodable {
        let type: String
        let mediaType: String
        let data: String

        enum CodingKeys: String, CodingKey {
            case type
            case mediaType = "media_type"
            case data
        }
    }

    static func buildAnthropicContentBlocks(
        text: String,
        attachments: [String],
        embedImages: Bool
    ) -> [AnthropicContentBlock] {
        var blocks: [AnthropicContentBlock] = []
        if !text.isEmpty {
            blocks.append(.textBlock(text))
        }
        for image in loadImagePayloads(from: attachments, embedImages: embedImages) {
            blocks.append(.imageBlock(payload: image))
        }
        if blocks.isEmpty {
            blocks.append(.textBlock(text))
        }
        return blocks
    }

    // MARK: - Codex Responses API

    static func buildCodexInputContent(
        text: String,
        attachments: [String],
        role: String,
        embedImages: Bool
    ) -> [[String: Any]] {
        let isAssistant = role == "assistant"
        let textType = isAssistant ? "output_text" : "input_text"
        var content: [[String: Any]] = []

        if !text.isEmpty {
            content.append([
                "type": textType,
                "text": text
            ])
        }

        if !isAssistant {
            for image in loadImagePayloads(from: attachments, embedImages: embedImages) {
                content.append([
                    "type": "input_image",
                    "image_url": image.dataURL
                ])
            }
        }

        if content.isEmpty {
            content.append([
                "type": textType,
                "text": text
            ])
        }

        return content
    }

    static func logSkippedAttachmentsIfNeeded(
        _ attachments: [String],
        providerLabel: String,
        embedImages: Bool
    ) {
        guard !attachments.isEmpty else { return }
        if !embedImages {
            DiagnosticsLogger.log(
                "Attachments skipped: model does not support vision",
                category: .network,
                metadata: [
                    "provider": providerLabel,
                    "attachment_count": String(attachments.count)
                ]
            )
            return
        }
        let embeddedCount = loadImagePayloads(from: attachments, embedImages: true).count
        if embeddedCount < attachments.count {
            DiagnosticsLogger.log(
                "Some attachments were not embedded for \(providerLabel)",
                category: .network,
                metadata: [
                    "attachment_count": String(attachments.count),
                    "embedded_count": String(embeddedCount)
                ]
            )
        }
    }
}
