package com.porarri.yamabikochat.data.model

sealed class ProviderClientError(message: String) : Exception(message) {
    data class MissingCredential(val provider: String) :
        ProviderClientError(
            if (provider.uppercase() == "GEMINI_OAUTH_CLIENT")
                "API credential is missing for the selected provider."
            else
                "Missing credential for $provider."
        )

    data class InvalidBaseURL(val url: String) :
        ProviderClientError("Invalid base URL: $url.")

    object InvalidResponse :
        ProviderClientError("Invalid API response.")

    data class HttpStatus(val status: Int, val body: String) :
        ProviderClientError("HTTP $status: $body")

    data class ParseFailure(val reason: String) :
        ProviderClientError("Response parse failed: $reason")

    data class UnsupportedModel(val provider: String, val model: String) :
        ProviderClientError("Unsupported model for $provider: $model.")
}
