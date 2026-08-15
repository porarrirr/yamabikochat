package com.porarri.yamabikochat.data.model

data class InlineData(
    val mimeType: String,
    val data: String
)

data class Part(
    val text: String? = null,
    val inlineData: InlineData? = null
)
