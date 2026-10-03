import AppIntents
import Foundation

struct AskYamabikoIntent: AppIntent {
    static var title: LocalizedStringResource = "やまびこに質問"
    static var description = IntentDescription("設定済みのプロバイダとモデルで質問し、回答を返します。")
    static var openAppWhenRun = false

    @Parameter(title: "質問", requestValueDialog: "何を質問しますか？")
    var prompt: String
    @Parameter(title: "新しい会話に保存", default: false)
    var saveToConversation: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("やまびこに\(\.$prompt)を質問") {
            \.$saveToConversation
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let result = try await SiriConversationService.ask(prompt: prompt, save: saveToConversation)
        return .result(value: result.text, dialog: IntentDialog(stringLiteral: result.text))
    }
}

struct OpenConversationIntent: AppIntent {
    static var openAppWhenRun = true
    static var title: LocalizedStringResource = "会話を開く"
    @Parameter(title: "会話") var target: ConversationEntity

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$target)を開く")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let entity = try SiriConversationService.resolve(
            id: Int64(target.id), repository: AppServices.resolve().conversationRepository)
        SiriNavigation.shared.request(.conversation(Int64(entity.id)))
        return .result()
    }
}

struct FindConversationsIntent: AppIntent {
    static var title: LocalizedStringResource = "会話を検索"
    static var openAppWhenRun = false
    @Parameter(title: "検索語") var term: String

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$term)で会話を検索")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[ConversationEntity]> {
        let entities = try await ConversationEntityQuery().entities(matching: term)
        return .result(value: entities)
    }
}

// Generic content access schemas fit AI conversations without representing them
// as messages sent to another person or as another unrelated domain.
@available(iOS 27.0, *)
@AppIntent(schema: .system.open)
struct SiriOpenConversationIntent: OpenIntent {
    static var title: LocalizedStringResource = "会話を表示"
    @Parameter(title: "会話") var target: ConversationEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = try SiriConversationService.resolve(
            id: Int64(target.id), repository: AppServices.resolve().conversationRepository)
        // URLRepresentableEntity routes the resolved target to the app.
        return .result()
    }
}

@available(iOS 27.0, *)
@AppIntent(schema: .system.searchInApp)
struct SiriSearchConversationsIntent: ShowInAppSearchResultsIntent {
    static var title: LocalizedStringResource = "アプリで会話を検索"
    static var searchScopes: [StringSearchScope] = [.general]
    @Parameter(title: "検索条件") var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        SiriNavigation.shared.request(.search(criteria.term))
        return .result()
    }
}
