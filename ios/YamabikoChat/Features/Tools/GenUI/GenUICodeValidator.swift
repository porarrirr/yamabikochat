import Foundation
import JavaScriptCore

enum GenUICodeValidator {
    private static let parser = Parser()

    /// Compile the function body without invoking it or exposing host APIs.
    static func validate(_ code: String) throws {
        try parser.validate(code)
    }

    private final class Parser {
        // Preview validation also runs outside the main actor. Serialize the
        // compile/exception pair; JavaScriptCore permits use from any thread.
        private let lock = NSLock()
        private let context = JSContext()
        private let compile: JSValue?

        init() {
            compile = context?.evaluateScript("""
                ((Function, String) => code => {
                    try { new Function('DIL', 'GenUI', 'state', 'resources', code); return null; }
                    catch (error) { return String(error); }
                })(Function, String)
                """)
        }

        func validate(_ code: String) throws {
            lock.lock()
            defer { lock.unlock() }
            try autoreleasepool {
                guard let context, let compile else {
                    throw GenUIError.invalid("JavaScript parser is unavailable")
                }
                context.exception = nil
                defer { context.exception = nil }
                // Pass source as a value, not an evaluated script. Constructing
                // a function only parses its body; generated code is never run.
                // Reuse the isolated context instead of starting a VM per delta.
                let result = compile.call(withArguments: [code])
                if let exception = context.exception {
                    throw GenUIError.invalid("JavaScript syntax: \(String((exception.toString() ?? "invalid code").prefix(300)))")
                }
                guard let result else { throw GenUIError.invalid("JavaScript parser is unavailable") }
                if !result.isNull {
                    throw GenUIError.invalid("JavaScript syntax: \(String((result.toString() ?? "invalid code").prefix(300)))")
                }
            }
        }
    }
}
