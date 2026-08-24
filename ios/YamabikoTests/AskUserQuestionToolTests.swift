import XCTest
import SwiftUI
@testable import YamabikoChat

final class AskUserQuestionToolTests: XCTestCase {
    @MainActor
    func testExecuteWaitsForStructuredAnswerAndReturnsItToPi() async throws {
        let coordinator = UserQuestionCoordinator()
        let tool = AskUserQuestionTool(coordinator: coordinator)
        let call = ToolCall(
            id: "call-1",
            name: AskUserQuestionTool.name,
            argumentsJSON: #"{"questions":[{"header":"Choose","id":"mode","multi_select":true,"options":[{"label":"Fast (Recommended)","description":"Finishes sooner."},{"label":"Careful"}],"question":"Which mode?"}]}"#
        )

        let execution = Task { try await tool.execute(call: call) }
        let pending = try await waitForPending(on: coordinator)
        XCTAssertEqual(pending.questions.first?.id, "mode")
        XCTAssertEqual(pending.questions.first?.multiSelect, true)

        coordinator.answer(
            AskUserQuestionAnswer(
                answers: [AskUserQuestionAnswerItem(id: "mode", selected: ["Fast (Recommended)"], custom: "quiet")]
            ),
            requestID: pending.id
        )
        let result = try await execution.value
        let answer = try JSONDecoder().decode(AskUserQuestionAnswer.self, from: Data(result.content.utf8))

        XCTAssertEqual(result.callId, "call-1")
        XCTAssertFalse(result.isError)
        XCTAssertEqual(answer.answers.first?.id, "mode")
        XCTAssertEqual(answer.answers.first?.selected, ["Fast (Recommended)"])
        XCTAssertEqual(answer.answers.first?.custom, "quiet")
        XCTAssertNil(coordinator.pending)
    }

    @MainActor
    func testCancelReturnsStableToolErrorThroughRegistry() async throws {
        let coordinator = UserQuestionCoordinator()
        let registry = LocalToolRegistry(executors: [AskUserQuestionTool(coordinator: coordinator)])
        let call = ToolCall(
            id: "call-cancel",
            name: AskUserQuestionTool.name,
            argumentsJSON: #"{"questions":[{"id":"confirm","question":"Continue?"}]}"#
        )

        let execution = Task { await registry.execute(call: call) }
        let pending = try await waitForPending(on: coordinator)
        coordinator.cancel(requestID: pending.id)
        let result = await execution.value

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("user cancelled ask_user_question"))
        XCTAssertNil(coordinator.pending)
    }

    func testDefinitionMatchesRequestedSchemaShape() throws {
        XCTAssertEqual(AskUserQuestionTool.definition.name, "ask_user_question")
        let data = Data(AskUserQuestionTool.definition.parametersJSON.utf8)
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(schema["required"] as? [String], ["questions"])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let questions = try XCTUnwrap(properties["questions"] as? [String: Any])
        let items = try XCTUnwrap(questions["items"] as? [String: Any])
        let itemProperties = try XCTUnwrap(items["properties"] as? [String: Any])
        XCTAssertNotNil(itemProperties["multi_select"])
        XCTAssertNotNil(itemProperties["options"])
    }

    @MainActor
    func testDuplicateQuestionIDsFailBeforePresentingUI() async {
        let coordinator = UserQuestionCoordinator()
        let tool = AskUserQuestionTool(coordinator: coordinator)
        let call = ToolCall(
            id: "call-invalid",
            name: AskUserQuestionTool.name,
            argumentsJSON: #"{"questions":[{"id":"same","question":"One?"},{"id":"same","question":"Two?"}]}"#
        )

        do {
            _ = try await tool.execute(call: call)
            XCTFail("Expected validation to fail")
        } catch {
            XCTAssertEqual(
                error as? AskUserQuestionError,
                .invalidArguments("ask_user_question question ids must be unique")
            )
        }
        XCTAssertNil(coordinator.pending)
    }

    @MainActor
    func testQuestionCardRendersAtPhoneWidth() async throws {
        let coordinator = UserQuestionCoordinator()
        let answerTask = Task {
            try await coordinator.ask(questions: [
                AskUserQuestionItem(
                    header: "旅行スタイル",
                    id: "trip_style",
                    options: [
                        AskUserQuestionOption(label: "のんびりリラックス", description: nil),
                        AskUserQuestionOption(label: "観光メイン (Recommended)", description: "定番スポットを効率よく巡ります。"),
                        AskUserQuestionOption(label: "アクティブ・冒険", description: nil),
                        AskUserQuestionOption(label: "グルメ旅", description: nil)
                    ],
                    question: "どんな旅行にしたいですか？"
                )
            ])
        }
        let pending = try await waitForPending(on: coordinator)
        let renderer = ImageRenderer(
            content: AskUserQuestionCard(coordinator: coordinator, rendersEditableField: false)
                .frame(width: 390, height: 700, alignment: .bottom)
                .padding(10)
                .background(Color.black)
                .preferredColorScheme(.dark)
        )
        renderer.scale = 3
        let image = try XCTUnwrap(renderer.uiImage)
        let png = try XCTUnwrap(image.pngData())
        let outputURL = URL(fileURLWithPath: "/tmp/yamabiko-ask-user-question-card.png")
        try png.write(to: outputURL, options: .atomic)

        XCTAssertGreaterThan(image.size.width, 380)
        XCTAssertGreaterThan(image.size.height, 690)
        coordinator.cancel(requestID: pending.id)
        _ = await answerTask.result
    }

    @MainActor
    private func waitForPending(
        on coordinator: UserQuestionCoordinator
    ) async throws -> UserQuestionCoordinator.PendingRequest {
        for _ in 0..<100 {
            if let pending = coordinator.pending { return pending }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try XCTUnwrap(coordinator.pending)
    }
}
