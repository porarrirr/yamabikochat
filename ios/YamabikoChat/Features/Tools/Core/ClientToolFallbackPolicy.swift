import Foundation

enum ClientToolFallbackPolicy {
    static func shouldRetryWithoutClientTools(
        error: Error,
        request: ProviderRequest,
        round: Int
    ) -> Bool {
        guard round == 1,
              request.tools.contains(where: { $0.type == "function" || $0.type == "function_declarations" }),
              case let ProviderClientError.httpStatus(status, body) = error,
              [400, 404, 422].contains(status)
        else {
            return false
        }

        let normalized = body.lowercased()
        let mentionsTools = normalized.contains("tool")
            || normalized.contains("function")
            || normalized.contains("additionalproperties")
        let explicitlyUnsupported = [
            "not support",
            "unsupported",
            "does not support",
            "unknown field",
            "unrecognized field",
            "unknown parameter",
            "unrecognized parameter",
            "cannot find field",
            "unknown name"
        ]
        .contains(where: normalized.contains)
        return mentionsTools && explicitlyUnsupported
    }

    static func removingClientTools(from request: ProviderRequest) -> ProviderRequest {
        var fallback = request
        fallback.tools.removeAll(where: { $0.type == "function" || $0.type == "function_declarations" })
        return fallback
    }
}
