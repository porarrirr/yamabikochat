import Foundation

/// Runs the exact recovered CEL parser/evaluator locally; it has no network or AI host APIs.
enum GenUICELRuntime {
    private static let lock = NSLock()
    private static let context = GenUICELCreate()

    static func evaluate(_ request: String) -> String {
        guard request.utf8.count <= 1_048_576 else {
            return #"{"error":"CEL input exceeds the local evaluation budget","kind":"CELExpressionError"}"#
        }
        lock.lock()
        defer { lock.unlock() }
        guard let context, let result = request.withCString({ GenUICELCalculate(context, $0) }) else {
            return #"{"error":"Original CEL runtime could not be initialized","kind":"CELExpressionError"}"#
        }
        defer { GenUICELFreeString(result) }
        return String(cString: result)
    }
}
