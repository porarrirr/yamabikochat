import Foundation

enum FusionJudgeParser {
    static func parse(_ raw: String) -> JudgeAnalysis? {
        let trimmed = extractJSON(from: raw)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let dto = try? decoder.decode(JudgeAnalysisDTO.self, from: data) else {
            return nil
        }
        return dto.toJudgeAnalysis()
    }

    static func extractJSON(from text: String) -> String {
        var candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("```") {
            candidate = candidate
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let start = candidate.firstIndex(of: "{"),
           let end = candidate.lastIndex(of: "}") {
            return String(candidate[start ... end])
        }
        return candidate
    }
}