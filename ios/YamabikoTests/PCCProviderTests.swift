import XCTest
import FoundationModels
import UIKit
import GRDB
@testable import YamabikoChat

final class PCCProviderTests: XCTestCase {
    func testLivePCCThroughPiWithImageAndFollowUp() async throws {
        guard ProcessInfo.processInfo.environment["YAMABIKO_PCC_LIVE_TEST"] == "1" else {
            throw XCTSkip("Opt-in test consumes two PCC requests on an entitled physical device")
        }
        let capability = await PCCProviderClient.capability()
        XCTAssertTrue(capability.available, capability.reason ?? "PCC unavailable")
        guard capability.available else { return }
        let image = await MainActor.run {
            UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32)).pngData { _ in
                UIColor.red.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 32, height: 32))
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        try image.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let user = ProviderRequestMessage(role: "user", content: "What color is this image? Answer in one sentence.", attachments: [url.path])
        let configuration = PiAgentConfiguration(provider: "apple-pcc", model: AppleIntelligenceModelCatalog.pccModel, thinkingLevel: "low")
        func run(_ messages: [ProviderRequestMessage]) async throws -> ProviderResponse {
            let request = ProviderRequest(model: AppleIntelligenceModelCatalog.pccModel, messages: messages)
            let stream = try await PiAgentRuntime.shared.stream(request: request, configuration: configuration, tools: LocalToolRegistry(executors: []))
            var completed: ProviderResponse?
            for try await event in stream {
                if case .completed(let response) = event { completed = response }
            }
            return try XCTUnwrap(completed)
        }
        let first = try await run([user])
        XCTAssertFalse(first.text.isEmpty)
        XCTAssertNil(first.usage?.cacheCreationInputTokens)
        let history = try XCTUnwrap(first.providerTranscript)
        let second = try await run([user] + history + [.init(role: "user", content: "Repeat the color you identified.")])
        XCTAssertFalse(second.text.isEmpty)
        XCTAssertNotNil(second.piExecution)
    }

    func testLivePCCCancellationThroughPi() async throws {
        guard ProcessInfo.processInfo.environment["YAMABIKO_PCC_LIVE_TEST"] == "1" else {
            throw XCTSkip("Opt-in cancellation test consumes one PCC request")
        }
        let firstToken = expectation(description: "PCC first token")
        let task = Task {
            let request = ProviderRequest(model: AppleIntelligenceModelCatalog.pccModel,
                messages: [.init(role: "user", content: "Write a long story in 100 numbered paragraphs about a journey through a forest.")])
            let configuration = PiAgentConfiguration(provider: "apple-pcc", model: request.model, thinkingLevel: "low")
            let stream = try await PiAgentRuntime.shared.stream(request: request, configuration: configuration, tools: LocalToolRegistry(executors: []))
            var receivedFirst = false
            for try await event in stream {
                if case .textDelta(let delta) = event, !delta.isEmpty, !receivedFirst {
                    receivedFirst = true
                    firstToken.fulfill()
                }
                if case .completed = event { XCTFail("Generation completed before cancellation") }
            }
            // AsyncThrowingStream may end normally when its consumer is cancelled.
            try Task.checkCancellation()
        }
        await fulfillment(of: [firstToken], timeout: 60)
        task.cancel()
        do { try await task.value }
        catch is CancellationError { return }
        catch { return XCTFail("Unexpected cancellation error: \(error)") }
        XCTFail("Cancellation did not terminate the request")
    }

    func testUnknownUsageSurvivesNormalizationAndAggregation() {
        XCTAssertNil(ProviderUsage().normalized().inputTokens)
        XCTAssertNil(ProviderUsage().normalized().totalTokens)
        let unknown = ProviderUsage(inputTokens: 10, outputTokens: 5)
        let known = ProviderUsage(inputTokens: 2, outputTokens: 3, cacheCreationInputTokens: 4)
        XCTAssertNil(unknown.adding(known).cacheCreationInputTokens)
        XCTAssertEqual(unknown.adding(known).inputTokens, 12)
    }

    func testPCCSettingsSurvivePersistenceAndProviderSwitchMap() throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let repository = SettingsRepository(dbQueue: database)
        var settings = try repository.load()
        settings.apiProvider = "APPLE_INTELLIGENCE"
        settings.defaultModel = AppleIntelligenceModelCatalog.pccModel
        settings.pccReasoningLevel = "deep"
        try repository.save(settings)
        let saved = try repository.load()
        XCTAssertEqual(saved.defaultModel, AppleIntelligenceModelCatalog.pccModel)
        XCTAssertEqual(saved.modelForProvider("APPLE_INTELLIGENCE"), AppleIntelligenceModelCatalog.pccModel)
        XCTAssertEqual(saved.pccReasoningLevel, "deep")
        var switched = saved
        switched.apiProvider = "GEMINI"
        XCTAssertEqual(switched.modelForProvider("APPLE_INTELLIGENCE"), AppleIntelligenceModelCatalog.pccModel)
    }

    func testExistingOnDeviceChoiceRemainsOnDevice() throws {
        var settings = AppSettings()
        settings.apiProvider = "APPLE_INTELLIGENCE"
        settings.defaultModel = AppleIntelligenceModelCatalog.displayModel
        let saved = settings.normalizedForPersistence()
        XCTAssertEqual(saved.defaultModel, AppleIntelligenceModelCatalog.displayModel)
        XCTAssertNil(saved.pccReasoningLevel)
    }

    func testNativeUsageAndUnknownCacheCountSurviveBridgeEncoding() throws {
        let value = ProviderUsage(inputTokens: 20, outputTokens: 8, totalTokens: 28, reasoningTokens: 3, cachedInputTokens: 5)
        let decoded = try JSONDecoder().decode(ProviderUsage.self, from: JSONEncoder().encode(value))
        XCTAssertNil(decoded.normalized().cacheCreationInputTokens)
        XCTAssertEqual(decoded.cachedInputTokens, 5)
    }

    func testStrictAttachmentConversionRejectsNonImages() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("document".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let request = ProviderRequest(model: AppleIntelligenceModelCatalog.pccModel,
                                      messages: [.init(role: "user", content: "Read", attachments: [url.path])])
        XCTAssertThrowsError(try PiAgentRuntime.makeRequest(request, strictImageAttachments: true)) {
            XCTAssertEqual(($0 as? PCCFailure)?.code, "pcc_attachment_unsupported")
        }
    }

    func testPCCUnavailableOnOlderOS() async throws {
        if #available(iOS 27.0, *) { throw XCTSkip("Older OS check runs on iOS 26") }
        let capability = await PCCProviderClient.capability()
        XCTAssertFalse(capability.available)
        XCTAssertEqual(capability.reason, "pcc_os_unsupported")
    }

    func testTranscriptPreservesRolesAndImageOrder() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Requires iOS 27 SDK runtime") }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { _ in UIColor.red.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 2, height: 2)) }
        let content: JSONValue = .array([
            .object(["type": .string("text"), "text": .string("Before")]),
            .object(["type": .string("image"), "data": .string(image.base64EncodedString()), "mimeType": .string("image/png")]),
            .object(["type": .string("text"), "text": .string("After")])
        ])
        let context = PCCNativeRequest.Context(systemPrompt: "Instructions", messages: [
            .init(role: "user", content: .string("Hello")),
            .init(role: "assistant", content: .array([.object(["type": .string("text"), "text": .string("Hi")])])),
            .init(role: "user", content: content)
        ])
        let entries = Array(try PCCSDK.transcript(context))
        XCTAssertEqual(entries.count, 4)
        guard case .instructions = entries[0], case .prompt = entries[1], case .response = entries[2],
              case .prompt(let prompt) = entries[3] else { return XCTFail("Roles were not preserved") }
        XCTAssertEqual(prompt.segments.count, 3)
        guard case .text(let before) = prompt.segments[0], case .attachment = prompt.segments[1],
              case .text(let after) = prompt.segments[2] else { return XCTFail("Image order changed") }
        XCTAssertEqual(before.content, "Before")
        XCTAssertEqual(after.content, "After")
    }

    func testTranscriptRejectsUnsupportedHistory() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Requires iOS 27 SDK runtime") }
        let context = PCCNativeRequest.Context(messages: [.init(role: "toolResult", content: .string("result"))])
        XCTAssertThrowsError(try PCCSDK.transcript(context)) {
            XCTAssertEqual(($0 as? PCCFailure)?.code, "pcc_history_unsupported")
        }
    }
}
