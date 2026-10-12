import Foundation
import JavaScriptCore

enum GenUICodeValidator {
    /// Compile the function body without invoking it or exposing host APIs.
    static func validate(_ code: String) throws {
        guard let context = JSContext(),
              let data = try? JSONEncoder().encode(code), let literal = String(data: data, encoding: .utf8) else {
            throw GenUIError.invalid("JavaScript parser is unavailable")
        }
        context.evaluateScript("new Function('DIL','GenUI','state','resources',\(literal))")
        if let exception = context.exception {
            throw GenUIError.invalid("JavaScript syntax: \(String((exception.toString() ?? "invalid code").prefix(300)))")
        }
    }
}
