package com.porarri.yamabikochat.data.remote

import kotlinx.serialization.Serializable

@Serializable
data class OpenAiCompatPreset(
    val name: String,
    val baseUrl: String
)

