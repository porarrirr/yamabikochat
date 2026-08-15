import Foundation

struct DuckDuckGoHTMLEngine: SearchEngine {
    static let resultLimit = 8
    static let requestTimeout: TimeInterval = 15

    private let httpClient: any WebToolHTTPClient

    init(httpClient: any WebToolHTTPClient = URLSessionWebToolHTTPClient()) {
        self.httpClient = httpClient
    }

    func search(query: String, locale: Locale, maxResults: Int) async throws -> [SearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            throw ProviderClientError.parseFailure("Search query is empty")
        }
        let limit = min(max(1, maxResults), Self.resultLimit)
        let region = Self.regionParameter(for: locale)

        do {
            let primary = try await fetch(
                endpoint: "https://html.duckduckgo.com/html/",
                query: normalizedQuery,
                region: region
            )
            let results = Self.parseResults(html: primary, maxResults: limit)
            if !results.isEmpty {
                return results
            }
            throw ProviderClientError.parseFailure("DuckDuckGo HTML returned no results")
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            DiagnosticsLogger.log(
                "DuckDuckGo HTML search failed; trying Lite",
                level: .warning,
                category: .network,
                metadata: ["query": normalizedQuery],
                error: error
            )
            do {
                let fallback = try await fetch(
                    endpoint: "https://lite.duckduckgo.com/lite/",
                    query: normalizedQuery,
                    region: region
                )
                let results = Self.parseResults(html: fallback, maxResults: limit)
                guard !results.isEmpty else {
                    let noResultsError = ProviderClientError.parseFailure("DuckDuckGo Lite returned no results")
                    DiagnosticsLogger.log(
                        "DuckDuckGo Lite returned no results",
                        level: .error,
                        category: .network,
                        metadata: ["query": normalizedQuery],
                        error: noResultsError
                    )
                    throw noResultsError
                }
                return results
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as ProviderClientError {
                if case let .parseFailure(message) = error,
                   message == "DuckDuckGo Lite returned no results" {
                    throw error
                }
                DiagnosticsLogger.log(
                    "DuckDuckGo Lite search failed",
                    level: .error,
                    category: .network,
                    metadata: ["query": normalizedQuery],
                    error: error
                )
                throw error
            } catch {
                DiagnosticsLogger.log(
                    "DuckDuckGo Lite search failed",
                    level: .error,
                    category: .network,
                    metadata: ["query": normalizedQuery],
                    error: error
                )
                throw error
            }
        }
    }

    static func parseResults(html: String, maxResults: Int = resultLimit) -> [SearchResult] {
        let anchorPattern = #"(?is)<a\b([^>]*\bclass\s*=\s*["'][^"']*(?:result__a|result-link)[^"']*["'][^>]*)>(.*?)</a>"#
        let genericLitePattern = #"(?is)<a\b([^>]*\brel\s*=\s*["']nofollow["'][^>]*)>(.*?)</a>"#
        let anchorMatches = matches(pattern: anchorPattern, in: html)
        let matchesToUse = anchorMatches.isEmpty ? matches(pattern: genericLitePattern, in: html) : anchorMatches
        var results: [SearchResult] = []
        var seenURLs: Set<String> = []

        for match in matchesToUse {
            guard match.numberOfRanges >= 3,
                  let attributesRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html)
            else {
                continue
            }
            let attributes = String(html[attributesRange])
            guard let href = attribute(named: "href", in: attributes),
                  let decodedURL = decodeResultURL(href),
                  seenURLs.insert(decodedURL).inserted
            else {
                continue
            }
            let title = HTMLTextExtractor.extract(from: String(html[titleRange]), maxCharacters: 300)
            guard !title.isEmpty else { continue }

            let suffixStart = Range(match.range(at: 0), in: html)?.upperBound ?? titleRange.upperBound
            let remaining = String(html[suffixStart...].prefix(2_000))
            let snippet = firstCapture(
                patterns: [
                    #"(?is)<(?:a|div|td)\b[^>]*class\s*=\s*["'][^"']*result__snippet[^"']*["'][^>]*>(.*?)</(?:a|div|td)>"#,
                    #"(?is)<td\b[^>]*class\s*=\s*["'][^"']*result-snippet[^"']*["'][^>]*>(.*?)</td>"#
                ],
                in: remaining
            )
            .map { HTMLTextExtractor.extract(from: $0, maxCharacters: 600) } ?? ""

            results.append(
                SearchResult(
                    title: title,
                    snippet: snippet,
                    url: decodedURL,
                    publishedAt: extractPublishedDate(from: snippet)
                )
            )
            if results.count >= min(max(1, maxResults), resultLimit) {
                break
            }
        }
        return results
    }

    static func decodeResultURL(_ rawValue: String) -> String? {
        let decodedEntityValue = HTMLTextExtractor.decodeEntities(rawValue)
        let absoluteValue: String
        if decodedEntityValue.hasPrefix("//") {
            absoluteValue = "https:\(decodedEntityValue)"
        } else if decodedEntityValue.hasPrefix("/") {
            absoluteValue = "https://duckduckgo.com\(decodedEntityValue)"
        } else {
            absoluteValue = decodedEntityValue
        }

        if let components = URLComponents(string: absoluteValue),
           components.host?.lowercased().hasSuffix("duckduckgo.com") == true,
           components.path == "/l/",
           let redirected = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
           let decoded = redirected.removingPercentEncoding,
           let url = URL(string: decoded),
           ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            return url.absoluteString
        }

        guard let url = URL(string: absoluteValue),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        else {
            return nil
        }
        return url.absoluteString
    }

    static func regionParameter(for locale: Locale) -> String {
        let language = locale.language.languageCode?.identifier.lowercased() ?? "en"
        let region = locale.region?.identifier.lowercased() ?? "us"
        if region == "jp" || language == "ja" {
            return "jp-jp"
        }
        return "\(region)-\(language)"
    }

    static func extractPublishedDate(from text: String) -> String? {
        let patterns = [
            #"(?<!\d)(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?!\d)"#,
            #"(?<!\d)(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let year = integerCapture(1, match: match, input: text),
                  let month = integerCapture(2, match: match, input: text),
                  let day = integerCapture(3, match: match, input: text),
                  let formatted = isoDate(year: year, month: month, day: day)
            else {
                continue
            }
            return formatted
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["MMM d, yyyy", "MMMM d, yyyy"] {
            formatter.dateFormat = format
            guard let regex = try? NSRegularExpression(
                pattern: #"(?i)\b(?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)\s+\d{1,2},\s+\d{4}\b"#
            ), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range, in: text),
            let date = formatter.date(from: String(text[range])) else {
                continue
            }
            let output = DateFormatter()
            output.calendar = formatter.calendar
            output.locale = formatter.locale
            output.timeZone = formatter.timeZone
            output.dateFormat = "yyyy-MM-dd"
            return output.string(from: date)
        }
        return nil
    }

    private func fetch(endpoint: String, query: String, region: String) async throws -> String {
        guard var components = URLComponents(string: endpoint) else {
            throw ProviderClientError.invalidBaseURL(endpoint)
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "kl", value: region),
            URLQueryItem(name: "kp", value: "1")
        ]
        guard let url = components.url else {
            throw ProviderClientError.invalidBaseURL(endpoint)
        }
        let (data, response) = try await httpClient.get(url: url, timeout: Self.requestTimeout)
        guard (200 ... 299).contains(response.statusCode) else {
            let httpError = ProviderClientError.httpStatus(
                response.statusCode,
                String(data: data, encoding: .utf8) ?? ""
            )
            DiagnosticsLogger.log(
                "DuckDuckGo search HTTP error",
                level: .error,
                category: .network,
                metadata: [
                    "endpoint": endpoint,
                    "status_code": String(response.statusCode)
                ],
                error: httpError
            )
            throw httpError
        }
        guard let html = String(data: data, encoding: .utf8) ??
            String(data: data, encoding: .isoLatin1)
        else {
            throw ProviderClientError.parseFailure("DuckDuckGo response encoding is unsupported")
        }
        return html
    }

    private static func matches(pattern: String, in input: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
    }

    private static func attribute(named name: String, in input: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let regex = try? NSRegularExpression(
            pattern: #"(?is)\b\#(escaped)\s*=\s*(["'])(.*?)\1"#
        ) else {
            return nil
        }
        guard let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
              let range = Range(match.range(at: 2), in: input)
        else {
            return nil
        }
        return String(input[range])
    }

    private static func firstCapture(patterns: [String], in input: String) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)),
                  let range = Range(match.range(at: 1), in: input)
            else {
                continue
            }
            return String(input[range])
        }
        return nil
    }

    private static func integerCapture(
        _ capture: Int,
        match: NSTextCheckingResult,
        input: String
    ) -> Int? {
        guard let range = Range(match.range(at: capture), in: input) else { return nil }
        return Int(input[range])
    }

    private static func isoDate(year: Int, month: Int, day: Int) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date).year == year,
              calendar.dateComponents([.year, .month, .day], from: date).month == month,
              calendar.dateComponents([.year, .month, .day], from: date).day == day
        else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
