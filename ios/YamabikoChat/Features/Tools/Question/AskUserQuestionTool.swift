import Foundation

struct AskUserQuestionOption: Codable, Sendable, Equatable {
    var label: String
    var description: String?
}

struct AskUserQuestionItem: Codable, Sendable, Equatable {
    var header: String?
    var id: String
    var multiSelect: Bool
    var options: [AskUserQuestionOption]
    var question: String

    private enum CodingKeys: String, CodingKey {
        case header, id, options, question
        case multiSelect = "multi_select"
    }

    init(
        header: String? = nil,
        id: String,
        multiSelect: Bool = false,
        options: [AskUserQuestionOption] = [],
        question: String
    ) {
        self.header = header
        self.id = id
        self.multiSelect = multiSelect
        self.options = options
        self.question = question
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        header = try container.decodeIfPresent(String.self, forKey: .header)
        id = try container.decode(String.self, forKey: .id)
        multiSelect = try container.decodeIfPresent(Bool.self, forKey: .multiSelect) ?? false
        options = try container.decodeIfPresent([AskUserQuestionOption].self, forKey: .options) ?? []
        question = try container.decode(String.self, forKey: .question)
    }
}

struct AskUserQuestionArguments: Codable, Sendable, Equatable {
    var questions: [AskUserQuestionItem]
}

struct AskUserQuestionAnswerItem: Codable, Sendable, Equatable {
    var id: String
    var selected: [String]
    var custom: String?
}

struct AskUserQuestionAnswer: Codable, Sendable, Equatable {
    var answers: [AskUserQuestionAnswerItem]
}

enum AskUserQuestionError: LocalizedError, Equatable {
    case cancelled
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "user cancelled ask_user_question"
        case let .invalidArguments(message):
            return message
        }
    }
}

final class UserQuestionCoordinator: ObservableObject, @unchecked Sendable {
    struct PendingRequest: Identifiable, Sendable, Equatable {
        var id: UUID
        var questions: [AskUserQuestionItem]
    }

    @Published private(set) var pending: PendingRequest?

    private struct WaitingRequest {
        var request: PendingRequest
        var continuation: CheckedContinuation<AskUserQuestionAnswer, Error>
    }

    private var waiting: [WaitingRequest] = []

    @MainActor
    func ask(questions: [AskUserQuestionItem]) async throws -> AskUserQuestionAnswer {
        try Task.checkCancellation()
        let request = PendingRequest(id: UUID(), questions: questions)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiting.append(WaitingRequest(request: request, continuation: continuation))
                presentNextIfNeeded()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel(requestID: request.id, error: CancellationError())
            }
        }
    }

    @MainActor
    func answer(_ answer: AskUserQuestionAnswer, requestID: UUID) {
        guard let index = waiting.firstIndex(where: { $0.request.id == requestID }) else { return }
        let continuation = waiting.remove(at: index).continuation
        if pending?.id == requestID { pending = nil }
        continuation.resume(returning: answer)
        presentNextIfNeeded()
    }

    @MainActor
    func cancel(requestID: UUID) {
        cancel(requestID: requestID, error: AskUserQuestionError.cancelled)
    }

    @MainActor
    private func cancel(requestID: UUID, error: Error) {
        guard let index = waiting.firstIndex(where: { $0.request.id == requestID }) else { return }
        let continuation = waiting.remove(at: index).continuation
        if pending?.id == requestID { pending = nil }
        continuation.resume(throwing: error)
        presentNextIfNeeded()
    }

    @MainActor
    private func presentNextIfNeeded() {
        if pending == nil { pending = waiting.first?.request }
    }
}

struct AskUserQuestionTool: LocalToolExecutor {
    static let name = "ask_user_question"

    static let definition = ToolDefinition(
        name: name,
        description: "Ask a concise question only when missing information materially affects the answer or an action requires the user's authorization. Use available context first; state a reasonable assumption for minor ambiguities. Send one or more questions with unique non-empty ids and non-empty question text. Options are optional; omit them for a free-text question. Use the user's language. Cancellation is not an answer or authorization.",
        parametersJSON: #"""
        {
          "type": "object",
          "properties": {
            "questions": {
              "type": "array",
              "items": {
                "type": "object",
                "properties": {
                  "header": {
                    "type": "string",
                    "description": "Optional short heading for the question, such as \"Confirm\" or \"Choose Mode\"."
                  },
                  "id": {
                    "type": "string",
                    "description": "Unique non-empty id within this call; echoed in the answer.",
                    "minLength": 1,
                    "pattern": "\\S"
                  },
                  "multi_select": {
                    "type": "boolean",
                    "description": "Whether the user may select more than one option. Defaults to false."
                  },
                  "options": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "properties": {
                        "label": {
                          "type": "string",
                          "description": "Short user-facing option label.",
                          "minLength": 1,
                          "pattern": "\\S"
                        },
                        "description": {
                          "type": "string",
                          "description": "One sentence explaining the tradeoff or impact."
                        }
                      },
                      "required": [
                        "label"
                      ],
                      "additionalProperties": false
                    }
                  },
                  "question": {
                    "type": "string",
                    "description": "The specific question to ask the user.",
                    "minLength": 1,
                    "pattern": "\\S"
                  }
                },
                "required": [
                  "id",
                  "question"
                ],
                "additionalProperties": false
              },
              "minItems": 1
            }
          },
          "required": [
            "questions"
          ]
        }
        """#
    )

    let coordinator: UserQuestionCoordinator

    var definition: ToolDefinition { Self.definition }

    func execute(call: ToolCall) async throws -> ToolResult {
        let arguments: AskUserQuestionArguments
        do {
            arguments = try JSONDecoder().decode(
                AskUserQuestionArguments.self,
                from: Data(call.argumentsJSON.utf8)
            )
        } catch {
            throw AskUserQuestionError.invalidArguments("Invalid ask_user_question arguments: \(error.localizedDescription)")
        }
        try Self.validate(arguments)
        let answer = try await coordinator.ask(questions: arguments.questions)
        let data = try JSONEncoder().encode(answer)
        return ToolResult(
            callId: call.id,
            name: call.name,
            content: String(decoding: data, as: UTF8.self)
        )
    }

    private static func validate(_ arguments: AskUserQuestionArguments) throws {
        guard !arguments.questions.isEmpty else {
            throw AskUserQuestionError.invalidArguments("ask_user_question requires at least one question")
        }
        var ids = Set<String>()
        for question in arguments.questions {
            guard !question.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AskUserQuestionError.invalidArguments("ask_user_question requires a non-empty id for every question")
            }
            guard ids.insert(question.id).inserted else {
                throw AskUserQuestionError.invalidArguments("ask_user_question question ids must be unique")
            }
            guard !question.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AskUserQuestionError.invalidArguments("ask_user_question requires non-empty question text")
            }
            guard question.options.allSatisfy({ !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw AskUserQuestionError.invalidArguments("ask_user_question option labels must be non-empty")
            }
        }
    }
}
