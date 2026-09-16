import Foundation
import FoundationModels

/// Compacts PCC history at a tool-output boundary, before Apple's native loop
/// starts its next inference. This is the only safe point at which the SDK
/// permits a lossy history mutation without replaying an already-run tool.
@available(iOS 27.0, *)
struct PCCContextCompactionModifier<Model: LanguageModel>: LanguageModelSession.DynamicProfileModifier {
    static var entryThreshold: Int { 12 }
    static var contextBudgetRatio: Double { 0.6 }

    let model: Model
    let contextSize: Int
    let recorder: PCCContextCompactionRecorder

    @LanguageModelSession.SessionProperty(\.history)
    private var history

    func body(content: Content) -> some LanguageModelSession.DynamicProfile {
        content.onToolOutput { _, output in
            // The callback runs immediately before the SDK appends this output
            // to history. Include it when deciding whether the call group is
            // complete, but leave the actual append to the SDK.
            let prospectiveHistory = Array(history) + [.toolOutput(output)]
            guard let plan = Self.plan(history: prospectiveHistory, contextSize: contextSize) else { return }
            let summarizer = LanguageModelSession(model: model, instructions: Instructions {
                """
                Compress the supplied conversation history into a concise continuation summary. Preserve the user's
                objective, decisions, exact names and values, completed work, important tool findings, open questions,
                and the next action. Do not invent facts and do not mention that a summary was created.
                """
            })
            let response = try await summarizer.respond(
                to: Prompt("Summarize this conversation for continuation:\n\n\(Self.render(plan.prefix))"),
                options: GenerationOptions(maximumResponseTokens: min(2_048, max(256, contextSize / 16)))
            )
            let summary = Transcript.Entry.response(.init(
                assetIDs: [],
                segments: [.text(.init(content: "Conversation memory:\n\(response.content)"))]
            ))
            history = [summary] + plan.retainedExchange.dropLast()
            let usage = PCCSDK.usage(summarizer.usage)
            await recorder.record(usage: usage, entriesRemoved: plan.prefix.count - 1)
            DiagnosticsLogger.log(
                "PCC tool-loop context compacted",
                category: .network,
                metadata: [
                    "contextSize": String(contextSize),
                    "estimatedTokens": String(plan.estimatedTokens),
                    "entriesBefore": String(plan.prefix.count + plan.retainedExchange.count),
                    "entriesAfter": String(1 + plan.retainedExchange.count)
                ]
            )
        }
    }

    struct Plan {
        let prefix: [Transcript.Entry]
        let retainedExchange: [Transcript.Entry]
        let estimatedTokens: Int
    }

    static func plan(history: [Transcript.Entry], contextSize: Int) -> Plan? {
        guard contextSize > 0,
              let callIndex = history.lastIndex(where: { if case .toolCalls = $0 { return true }; return false })
        else { return nil }
        let retained = Array(history[callIndex...])
        guard completedToolExchange(retained), callIndex > history.startIndex else { return nil }
        let estimatedTokens = render(history).unicodeScalars.count
        let budget = Int(Double(contextSize) * contextBudgetRatio)
        guard history.count > entryThreshold || estimatedTokens >= budget else { return nil }
        return Plan(prefix: Array(history[..<callIndex]), retainedExchange: retained, estimatedTokens: estimatedTokens)
    }

    private static func completedToolExchange(_ entries: [Transcript.Entry]) -> Bool {
        let callIDs = Set(entries.flatMap { entry -> [String] in
            guard case .toolCalls(let calls) = entry else { return [] }
            return calls.map(\.id)
        })
        let outputIDs = Set(entries.compactMap { entry -> String? in
            guard case .toolOutput(let output) = entry else { return nil }
            return output.id
        })
        return !callIDs.isEmpty && callIDs.isSubset(of: outputIDs)
    }

    static func render(_ entries: [Transcript.Entry]) -> String {
        entries.compactMap { entry in
            switch entry {
            case .prompt(let value): return "User: \(text(value.segments))"
            case .response(let value): return "Assistant: \(text(value.segments))"
            case .reasoning(let value): return "Assistant reasoning: \(text(value.segments))"
            case .toolCalls(let calls):
                return "Tool calls: " + calls.map { "\($0.toolName)(\($0.arguments))" }.joined(separator: ", ")
            case .toolOutput(let value): return "Tool output (\(value.toolName)): \(text(value.segments))"
            case .instructions: return nil
            @unknown default: return nil
            }
        }.joined(separator: "\n")
    }

    private static func text(_ segments: [Transcript.Segment]) -> String {
        segments.map { segment in
            switch segment {
            case .text(let value): return value.content
            case .attachment: return "[attachment]"
            case .structure(let value): return String(describing: value.content)
            @unknown default: return ""
            }
        }.joined(separator: " ")
    }
}

@available(iOS 27.0, *)
actor PCCContextCompactionRecorder {
    private(set) var count = 0
    private(set) var usage = ProviderUsage(inputTokens: 0, outputTokens: 0, totalTokens: 0,
                                           reasoningTokens: 0, cachedInputTokens: 0)

    func record(usage added: ProviderUsage, entriesRemoved: Int) {
        count += 1
        usage = PCCSDK.addUsage(usage, added)
    }
}
