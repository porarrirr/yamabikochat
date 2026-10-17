import Foundation

/// Public search pages only: no credentials, proxy, or model execution.
struct PublicHTMLSearchEngine: SearchEngine {
    enum Provider: String, Sendable { case yahooJapan = "yahoo_japan", bing }
    let provider: Provider
    var httpClient: any WebToolHTTPClient = URLSessionWebToolHTTPClient()

    func search(query: String, locale: Locale, maxResults: Int) async throws -> [SearchResult] {
        let japanese = FederatedSearchEngine.prefersJapanese(query: query, locale: locale)
        var components = URLComponents(string: provider == .yahooJapan
            ? "https://search.yahoo.co.jp/search" : "https://www.bing.com/search")!
        components.queryItems = provider == .yahooJapan
            ? [URLQueryItem(name: "p", value: query), URLQueryItem(name: "ei", value: "UTF-8")]
            : [URLQueryItem(name: "q", value: query),
               URLQueryItem(name: "setlang", value: japanese ? "ja-JP" : locale.identifier.replacingOccurrences(of: "_", with: "-")),
               URLQueryItem(name: "cc", value: japanese ? "JP" : locale.region?.identifier ?? "US"),
               URLQueryItem(name: "adlt", value: "moderate")]
        let (data, response) = try await httpClient.get(url: components.url!, timeout: 6)
        try Task.checkCancellation()
        guard (200...299).contains(response.statusCode), let html = String(data: data, encoding: .utf8) else {
            throw ProviderClientError.parseFailure("\(provider.rawValue) search HTTP \(response.statusCode)")
        }
        let results = Self.parse(html: html, provider: provider, maxResults: maxResults)
        guard !results.isEmpty else {
            throw ProviderClientError.parseFailure("\(provider.rawValue) returned no readable organic results (empty, restricted, or changed markup)")
        }
        return results
    }

    static func parse(html: String, provider: Provider, maxResults: Int = 8) -> [SearchResult] {
        // Limit extraction to organic cards. Ads, AI answers, navigation and
        // related questions must never become attributed source evidence.
        let pattern = provider == .yahooJapan
            ? #"(?is)<div\b[^>]*class=["'][^"']*\bAlgo\s+Algo-[^"']*["'][^>]*>\s*<section\b[^>]*>(.*?)</section>"#
            : #"(?is)<li\b[^>]*class=["'][^"']*\bb_algo\b[^"']*["'][^>]*>(.*?)</li>"#
        return captures(pattern, in: html).compactMap { block in
            let heading = first(#"(?is)<h[23]\b[^>]*>(.*?)</h[23]>"#, in: block)
            let enclosingHeadingLink = captures(#"(?is)(<a\b[^>]*>(?:(?!</a>).)*<h2\b(?:(?!</a>).)*</a>)"#, in: block).first
            let linkArea = provider == .bing ? enclosingHeadingLink ?? heading ?? "" : block
            guard let raw = first(#"(?is)<a\b[^>]*\bhref\s*=\s*["']([^"']+)["']"#, in: linkArea),
                  let url = destination(raw, provider: provider), let heading else { return nil }
            let title = HTMLTextExtractor.extract(from: heading, maxCharacters: 300)
            guard !title.isEmpty else { return nil }
            let snippet = first(#"(?is)<p\b[^>]*>(.*?)</p>"#, in: block)
                .map { HTMLTextExtractor.extract(from: $0, maxCharacters: 600) } ?? ""
            return SearchResult(title: title, snippet: snippet, url: url,
                                searchEngines: [provider.rawValue])
        }.prefix(max(1, min(maxResults, 16))).map { $0 }
    }

    static func destination(_ raw: String, provider: Provider) -> String? {
        var value = HTMLTextExtractor.decodeEntities(raw)
        if provider == .bing, let components = URLComponents(string: value),
           ["bing.com", "www.bing.com"].contains(components.host?.lowercased() ?? ""), components.path == "/ck/a" {
            guard var encoded = components.queryItems?.first(where: { $0.name == "u" })?.value else { return nil }
            if encoded.hasPrefix("a1") { encoded = String(encoded.dropFirst(2)) }
            encoded = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
            guard let data = Data(base64Encoded: encoded), let decoded = String(data: data, encoding: .utf8) else { return nil }
            value = decoded
        }
        guard let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url.absoluteString
    }

    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
    private static func first(_ pattern: String, in text: String) -> String? { captures(pattern, in: text).first }
}

struct FederatedSearchEngine: SearchEngine {
    let japaneseEngine: any SearchEngine
    let globalEngine: any SearchEngine
    let fallback: any SearchEngine
    var budget: Duration = .seconds(8)

    init(japaneseEngine: any SearchEngine = PublicHTMLSearchEngine(provider: .yahooJapan),
         globalEngine: any SearchEngine = PublicHTMLSearchEngine(provider: .bing),
         fallback: any SearchEngine = DuckDuckGoHTMLEngine(), budget: Duration = .seconds(8)) {
        self.japaneseEngine = japaneseEngine
        self.globalEngine = globalEngine
        self.fallback = fallback
        self.budget = budget
    }

    func search(query: String, locale: Locale, maxResults: Int) async throws -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderClientError.parseFailure("Search query is empty")
        }
        let japanese = Self.prefersJapanese(query: query, locale: locale)
        let engines = japanese ? [japaneseEngine, globalEngine] : [globalEngine]
        // A single deadline includes the fallback. Completed batches survive a
        // slow/restricted provider; URLSession cancellation closes pending work.
        let batches = await withTaskGroup(of: (Int, [SearchResult])?.self) { group in
            group.addTask { try? await Task.sleep(for: budget); return nil }
            for (index, engine) in engines.enumerated() {
                group.addTask {
                    do { return (index, try await engine.search(query: query, locale: locale, maxResults: 16)) }
                    catch {
                        if !Task.isCancelled {
                            DiagnosticsLogger.log("Public search provider unavailable", level: .warning, category: .network,
                                                  metadata: ["provider_index": String(index)], error: error)
                        }
                        return (index, [])
                    }
                }
            }
            var collected: [(Int, [SearchResult])] = []
            var remaining = engines.count
            var fallbackStarted = false
            while let event = await group.next() {
                guard let batch = event else { break }
                collected.append(batch)
                remaining -= 1
                if remaining == 0 {
                    if collected.allSatisfy({ $0.1.isEmpty }), !fallbackStarted {
                        fallbackStarted = true
                        remaining = 1
                        group.addTask { (engines.count, (try? await fallback.search(query: query, locale: japanese ? Locale(identifier: "ja_JP") : locale, maxResults: 8)) ?? []) }
                    } else { break }
                }
            }
            group.cancelAll()
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
        try Task.checkCancellation()
        let results = Self.merge(batches, query: query, japanese: japanese, maxResults: maxResults)
        guard !results.isEmpty else {
            throw ProviderClientError.parseFailure("Public search unavailable: no readable results within the search budget")
        }
        return results
    }

    static func prefersJapanese(query: String, locale: Locale) -> Bool {
        locale.language.languageCode?.identifier == "ja" || query.unicodeScalars.contains {
            (0x3040...0x30ff).contains($0.value) || (0x3400...0x9fff).contains($0.value)
        }
    }

    static func canonicalURL(_ raw: String) -> String? {
        guard var url = URLComponents(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, url.user == nil, url.password == nil else { return nil }
        url.host = host.lowercased()
        let tracking: Set<String> = ["gclid", "fbclid", "msclkid", "mc_cid", "mc_eid", "igshid"]
        url.queryItems = url.queryItems?.filter { !tracking.contains($0.name.lowercased()) && !$0.name.lowercased().hasPrefix("utm_") }
        if url.queryItems?.isEmpty == true { url.queryItems = nil }
        // Preserve resource parameters, path case, and fragments (SPA routes).
        return url.string
    }

    static func merge(_ batches: [[SearchResult]], query: String, japanese: Bool, maxResults: Int) -> [SearchResult] {
        var hits: [String: SearchResult] = [:]
        var scores: [String: Double] = [:]
        let terms = query.precomposedStringWithCompatibilityMapping.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        for (engine, batch) in batches.enumerated() {
            var seen: Set<String> = []
            for (rank, hit) in batch.enumerated() {
                guard let key = canonicalURL(hit.url), seen.insert(key).inserted else { continue }
                if var existing = hits[key] {
                    existing.searchEngines = Array(Set(existing.searchEngines + hit.searchEngines)).sorted()
                    if existing.snippet.isEmpty { existing.snippet = hit.snippet }
                    hits[key] = existing
                } else {
                    var clean = hit; clean.url = key; hits[key] = clean
                }
                let text = (hit.title + " " + hit.snippet).precomposedStringWithCompatibilityMapping.lowercased()
                let overlap = Double(terms.filter { text.contains($0) }.count) / Double(max(1, terms.count))
                scores[key, default: 0] += (japanese && engine == 0 ? 1.2 : 1) / Double(10 + rank) + overlap * 0.025
            }
        }
        var selected: [SearchResult] = []
        var domains: [String: Int] = [:]
        while !hits.isEmpty, selected.count < max(1, min(maxResults, 8)) {
            let ordered = hits.keys.sorted { a, b in
                func score(_ key: String) -> Double {
                    (scores[key] ?? 0) / (1 + Double(domains[URL(string: key)?.host ?? "", default: 0]) * 0.65)
                }
                return score(a) == score(b) ? a < b : score(a) > score(b)
            }
            let key = ordered[0]
            selected.append(hits.removeValue(forKey: key)!)
            domains[URL(string: key)?.host ?? "", default: 0] += 1
        }
        return selected
    }
}
