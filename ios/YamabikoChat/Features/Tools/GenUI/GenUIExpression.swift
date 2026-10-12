import Foundation

enum GenUIError: LocalizedError, Equatable {
    case invalid(String)
    var errorDescription: String? { if case let .invalid(message) = self { return "Invalid genui: \(message)" }; return nil }
}

/// A bounded arithmetic parser. Never evaluates JavaScript, predicates, or native code.
enum GenUIExpression {
    static func evaluate(_ expression: String, values: [String: Double]) throws -> Double {
        guard expression.count <= 1024 else { throw GenUIError.invalid("formula is too long") }
        var parser = Parser(source: Array(expression.hasPrefix("=") ? expression.dropFirst() : expression[...]), values: values)
        let result = try parser.sum()
        parser.space()
        guard parser.index == parser.source.count, result.isFinite else { throw GenUIError.invalid("formula has invalid syntax or a non-finite result") }
        return result
    }

    private struct Parser {
        let source: [Character]
        let values: [String: Double]
        var index = 0
        var depth = 0
        mutating func space() { while index < source.count && source[index].isWhitespace { index += 1 } }
        mutating func take(_ character: Character) -> Bool {
            space()
            guard index < source.count, source[index] == character else { return false }
            index += 1
            return true
        }
        mutating func sum() throws -> Double {
            var value = try product()
            while true {
                if take("+") { value += try product() }
                else if take("-") { value -= try product() }
                else { return value }
            }
        }
        mutating func product() throws -> Double {
            var value = try unary()
            while true {
                if take("*") { value *= try unary() }
                else if take("/") { value /= try unary() }
                else { return value }
            }
        }
        mutating func unary() throws -> Double {
            depth += 1
            defer { depth -= 1 }
            guard depth <= 32 else { throw GenUIError.invalid("formula nesting exceeds 32") }
            if take("+") { return try unary() }
            if take("-") { return try -unary() }
            var value = try atom()
            if take("^") { value = Foundation.pow(value, try unary()) }
            return value
        }
        mutating func atom() throws -> Double {
            if take("(") {
                let value = try sum()
                guard take(")") else { throw GenUIError.invalid("missing closing parenthesis") }
                return value
            }
            space()
            let start = index
            if index < source.count, source[index].isLetter || source[index] == "_" {
                while index < source.count && (source[index].isLetter || source[index].isNumber || source[index] == "_") { index += 1 }
                let name = String(source[start..<index])
                if !take("(") {
                    guard let value = values[name], value.isFinite else { throw GenUIError.invalid("unknown numeric input \(name)") }
                    return value
                }
                var args: [Double] = []
                if !take(")") {
                    repeat { args.append(try sum()); guard args.count <= 8 else { throw GenUIError.invalid("too many function arguments") } } while take(",")
                    guard take(")") else { throw GenUIError.invalid("missing function closing parenthesis") }
                }
                switch (name, args.count) {
                case ("min", 2): return min(args[0], args[1])
                case ("max", 2): return max(args[0], args[1])
                case ("abs", 1): return abs(args[0])
                case ("round", 1): return args[0].rounded()
                case ("pow", 2): return Foundation.pow(args[0], args[1])
                case ("payment", 3):
                    guard args[0] >= 0, args[1] >= 0, args[2] > 0 else { throw GenUIError.invalid("payment requires nonnegative principal/rate and positive years") }
                    let months = args[2] * 12
                    let rate = args[1] / 1200
                    return rate == 0 ? args[0] / months : args[0] * rate / -Foundation.expm1(-months * Foundation.log1p(rate))
                default: throw GenUIError.invalid("unknown function or argument count: \(name)")
                }
            }
            while index < source.count && (source[index].isNumber || source[index] == ".") { index += 1 }
            if index < source.count && (source[index] == "e" || source[index] == "E") {
                index += 1
                if index < source.count && (source[index] == "+" || source[index] == "-") { index += 1 }
                while index < source.count && source[index].isNumber { index += 1 }
            }
            guard start < index, let number = Double(String(source[start..<index])), number.isFinite else { throw GenUIError.invalid("expected a number or input") }
            return number
        }
    }
}
