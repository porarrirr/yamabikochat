import Foundation

/// Parses the usage dialects returned by OpenAI-compatible providers.
/// `inputTokens` intentionally remains the provider's inclusive prompt count;
/// accounting converts it to disjoint DSH-style buckets exactly once.
enum OpenAICompatibleUsageParser {
    static func parse(_ object: [String: Any]?) -> ProviderUsage? {
        guard let object else { return nil }
        let completionDetails = object["completion_tokens_details"] as? [String: Any]
        let outputDetails = object["output_tokens_details"] as? [String: Any]
        let promptDetails = object["prompt_tokens_details"] as? [String: Any]
        let inputDetails = object["input_tokens_details"] as? [String: Any]

        return ProviderUsage(
            inputTokens: int(in: object, keys: ["prompt_tokens", "input_tokens", "promptTokens", "inputTokens"]),
            outputTokens: int(in: object, keys: ["completion_tokens", "output_tokens", "completionTokens", "outputTokens"]),
            totalTokens: int(in: object, keys: ["total_tokens", "totalTokens"]),
            reasoningTokens:
                int(in: object, keys: ["reasoning_tokens", "reasoningTokens", "reasoning_token_count", "reasoningTokenCount"]) ??
                int(in: completionDetails, keys: ["reasoning_tokens", "reasoningTokens", "reasoning", "reasoning_token_count"]) ??
                int(in: outputDetails, keys: ["reasoning_tokens", "reasoningTokens", "reasoning", "reasoning_token_count"]),
            cachedInputTokens:
                int(in: promptDetails, keys: ["cached_tokens", "cachedTokens", "cached_input_tokens", "cachedInputTokens"]) ??
                int(in: inputDetails, keys: ["cached_tokens", "cachedTokens", "cached_input_tokens", "cachedInputTokens"]) ??
                int(
                    in: object,
                    keys: [
                        "prompt_cache_hit_tokens", "cache_read_input_tokens", "cacheReadInputTokens",
                        "cached_input_tokens", "cachedInputTokens"
                    ]
                ),
            cacheCreationInputTokens:
                int(in: promptDetails, keys: ["cache_write_tokens", "cacheWriteTokens", "cache_creation_tokens", "cacheCreationTokens", "cache_creation_input_tokens"]) ??
                int(in: inputDetails, keys: ["cache_write_tokens", "cacheWriteTokens", "cache_creation_tokens", "cacheCreationTokens", "cache_creation_input_tokens"]) ??
                int(in: object, keys: ["cache_write_tokens", "cacheWriteTokens", "cache_creation_input_tokens", "cacheCreationInputTokens", "cache_creation_input_token_count"])
        )
        .normalizedNonEmpty()
    }

    private static func int(in object: [String: Any]?, keys: [String]) -> Int? {
        guard let object else { return nil }
        for key in keys {
            if let value = int(object[key]) { return value }
        }
        return nil
    }

    private static func int(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String { return Int(value) }
        return nil
    }
}
