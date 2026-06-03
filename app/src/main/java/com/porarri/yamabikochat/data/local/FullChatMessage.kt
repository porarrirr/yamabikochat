package com.porarri.yamabikochat.data.local

data class FullChatMessage(
    val chatMessage: ChatMessage,
    val thinkingStream: String? = null,
    val variants: List<ChatMessageVariant> = emptyList()
) {
    val variantCount: Int
        get() = 1 + variants.size

    val normalizedSelectedVariantIndex: Int
        get() = chatMessage.selectedVariantIndex.coerceIn(0, (variantCount - 1).coerceAtLeast(0))

    val selectedVariant: ChatMessageVariant?
        get() = variants.firstOrNull { it.variantIndex == normalizedSelectedVariantIndex }

    val displayText: String
        get() = selectedVariant?.text ?: chatMessage.text

    val displayAttachments: List<String>
        get() = selectedVariant?.attachments ?: chatMessage.attachments

    val displayThinkingStream: String?
        get() = if (normalizedSelectedVariantIndex == 0) thinkingStream else selectedVariant?.thinkingStream
}
