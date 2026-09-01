import Foundation
import XCTest
@testable import YamabikoChat

final class AgentSkillRepositoryTests: XCTestCase {
    private var temporaryRoot: URL!
    private var repository: AgentSkillRepository!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-skill-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        repository = AgentSkillRepository(rootURL: temporaryRoot.appendingPathComponent("installed"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testManifestInventoryInstallAndExplicitOrder() throws {
        let source = try makeSkill(
            name: "review-helper",
            descriptionYAML: ">\n  Review changes carefully\n  and report risks.",
            extraFiles: [
                "references/checklist.md": "Check every edge case.",
                "scripts/audit.py": "#!/usr/bin/env python3\nprint('never run locally')",
            ],
            extraFrontMatter: """
            license: MIT
            compatibility: Requires git
            allowed-tools:
              - shell
              - read
            metadata:
              author: Example
            """
        )

        let preview = try repository.inspect(sourceURL: source)
        XCTAssertEqual(preview.manifest.name, "review-helper")
        XCTAssertTrue(preview.manifest.description.contains("Review changes carefully"))
        XCTAssertEqual(preview.manifest.allowedTools, ["shell", "read"])
        XCTAssertEqual(preview.manifest.metadata["author"], "Example")
        XCTAssertTrue(preview.hasScripts)
        XCTAssertEqual(preview.files.map(\.path), ["SKILL.md", "references/checklist.md", "scripts/audit.py"])
        XCTAssertThrowsError(try repository.install(preview, trusted: false, allowReplacement: false))

        _ = try repository.install(preview, trusted: true, allowReplacement: false)
        let context = try XCTUnwrap(repository.requestContext(
            for: "@review-helper then @review-helper and @unknown",
            conversationID: "42",
            providerSupportsTools: true
        ))
        XCTAssertEqual(context.explicitlyRequestedNames, ["review-helper"])
        XCTAssertEqual(context.skillFilePaths.count, 1)
        XCTAssertEqual(context.explicitMessageIndices, [0])
        XCTAssertTrue(context.skillFilePaths[0].hasSuffix("review-helper/SKILL.md"))
        XCTAssertEqual(context.catalog.map(\.name), ["review-helper"])
        XCTAssertTrue(context.explicitInstructions[0].contains("Follow these instructions"))
        XCTAssertEqual(try repository.readResource(name: "review-helper", path: "references/checklist.md"), "Check every edge case.")
        XCTAssertThrowsError(try repository.readResource(name: "review-helper", path: "../outside.txt"))
    }

    func testEnabledStatePersistsAndReplacementPreservesIt() throws {
        let first = try repository.inspect(sourceURL: makeSkill(name: "stable-skill"))
        _ = try repository.install(first, trusted: true, allowReplacement: false)
        try repository.setEnabled(false, name: "stable-skill")

        let replacementSource = try makeSkill(
            name: "stable-skill",
            extraFiles: ["references/new.md": "replacement"]
        )
        let replacement = try repository.inspect(sourceURL: replacementSource)
        XCTAssertTrue(replacement.replacesExisting)
        _ = try repository.install(replacement, trusted: true, allowReplacement: true)
        XCTAssertFalse(try XCTUnwrap(repository.installedSkills.first).isEnabled)

        let reloaded = AgentSkillRepository(rootURL: temporaryRoot.appendingPathComponent("installed"))
        XCTAssertFalse(try XCTUnwrap(reloaded.installedSkills.first).isEnabled)
        try reloaded.delete(name: "stable-skill")
        XCTAssertTrue(reloaded.installedSkills.isEmpty)
    }

    func testRejectsMultipleSkillFilesAndSymlinks() throws {
        let multiple = try makeSkill(name: "multiple")
        let nested = multiple.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("---\nname: nested\ndescription: nested\n---\n".utf8)
            .write(to: nested.appendingPathComponent("SKILL.md"))
        XCTAssertThrowsError(try repository.inspect(sourceURL: multiple))

        let linked = try makeSkill(name: "linked")
        try FileManager.default.createSymbolicLink(
            at: linked.appendingPathComponent("escape.txt"),
            withDestinationURL: temporaryRoot.appendingPathComponent("outside.txt")
        )
        XCTAssertThrowsError(try repository.inspect(sourceURL: linked))
    }

    func testRejectsInvalidNameAndOversizedSkillFile() throws {
        let invalid = try makeSkill(name: "Invalid_Name")
        XCTAssertThrowsError(try repository.inspect(sourceURL: invalid))

        let oversized = try makeSkill(name: "too-large")
        let header = "---\nname: too-large\ndescription: oversized\n---\n"
        let body = String(repeating: "x", count: Int(AgentSkillLimits.skillFileBytes))
        try Data((header + body).utf8).write(to: oversized.appendingPathComponent("SKILL.md"))
        XCTAssertThrowsError(try repository.inspect(sourceURL: oversized))
    }

    func testSkillToolsAreExcludedFromInternalProviderScope() async throws {
        let preview = try repository.inspect(sourceURL: makeSkill(name: "scoped-skill"))
        _ = try repository.install(preview, trusted: true, allowReplacement: false)
        let resolver = ProviderRequestSettingsResolver(
            modelService: OpenRouterModelService(credentialStore: KeychainStore()),
            skillRepository: repository
        )

        let panel = try await resolver.resolve(
            settings: AppSettings(),
            provider: "OPENAI",
            model: "gpt-5.6",
            toolScope: .fusionPanel(allowWebSearch: false)
        )
        let internalRequest = try await resolver.resolve(
            settings: AppSettings(),
            provider: "OPENAI",
            model: "gpt-5.6",
            toolScope: .providerOnly
        )

        XCTAssertTrue(panel.tools.contains { $0.payload["name"] == AgentSkillTools.activateName })
        XCTAssertTrue(panel.tools.contains { $0.payload["name"] == AgentSkillTools.readResourceName })
        XCTAssertFalse(internalRequest.tools.contains { $0.payload["name"] == AgentSkillTools.activateName })
    }

    func testPromptComposerKeepsPreviouslySentUserMessagesByteStableAcrossTurns() throws {
        let preview = try repository.inspect(sourceURL: makeSkill(name: "stable-skill"))
        _ = try repository.install(preview, trusted: true, allowReplacement: false)
        let firstSource = [
            ProviderRequestMessage(role: "user", content: "@stable-skill review this")
        ]
        let first = try AgentSkillPromptComposer.apply(
            repository: repository,
            to: firstSource,
            conversationID: "conversation-1",
            providerSupportsTools: true
        )
        let secondSource = [
            ProviderRequestMessage(role: "user", content: "@stable-skill review this"),
            ProviderRequestMessage(role: "assistant", content: "first answer"),
            ProviderRequestMessage(role: "user", content: "continue")
        ]
        let second = try AgentSkillPromptComposer.apply(
            repository: repository,
            to: secondSource,
            conversationID: "conversation-1",
            providerSupportsTools: true
        )

        XCTAssertEqual(first.messages[0].content, second.messages[0].content)
        XCTAssertTrue(first.messages[0].content.hasPrefix("<available_agent_skills>"))
        XCTAssertTrue(first.messages[0].content.contains("@stable-skill review this"))
        XCTAssertFalse(first.messages[0].content.contains("<explicit_agent_skill"))
        XCTAssertFalse(second.messages[2].content.contains("<available_agent_skills>"))
        XCTAssertEqual(second.currentContext?.explicitMessageIndices, [0])
    }

    func testAtMentionAutocompleteAndLegacyDollarInvocation() throws {
        XCTAssertEqual(AgentSkillInvocationSyntax.autocompletePrefix(in: "@"), "")
        XCTAssertEqual(AgentSkillInvocationSyntax.autocompletePrefix(in: "Please @rev"), "rev")
        XCTAssertNil(AgentSkillInvocationSyntax.autocompletePrefix(in: "mail@example.com"))
        XCTAssertEqual(
            AgentSkillInvocationSyntax.completingAutocomplete(in: "Please @rev", with: "review-helper"),
            "Please @review-helper "
        )
        XCTAssertEqual(
            AgentSkillRepository.explicitSkillNames(
                in: "@review-helper and $legacy-skill, not mail@review-helper.com",
                allowed: ["review-helper", "legacy-skill"]
            ),
            ["review-helper", "legacy-skill"]
        )
    }

    private func makeSkill(
        name: String,
        descriptionYAML: String = "A test skill",
        extraFiles: [String: String] = [:],
        extraFrontMatter: String = ""
    ) throws -> URL {
        let source = temporaryRoot.appendingPathComponent("source-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let markdown = "---\nname: \(name)\ndescription: \(descriptionYAML)\n"
            + extraFrontMatter
            + "\n---\nFollow these instructions for \(name).\n"
        try Data(markdown.utf8).write(to: source.appendingPathComponent("SKILL.md"))
        for (path, content) in extraFiles {
            let url = source.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return source
    }
}
