import XCTest
import GRDB
@testable import YamabikoChat

final class OpenRouterReasoningChoiceTests: XCTestCase {
    func testEffortsAreOrderedFromLowToHighWithAutomaticLast() {
        let capabilities = OpenRouterReasoningCapabilities(
            supportedEfforts: ["max", "xhigh", "high", "low"], exposesEffortSelection: true
        )
        XCTAssertEqual(OpenRouterReasoningChoice.options(for: capabilities), [
            .effort("low"), .effort("high"), .effort("xhigh"), .effort("max"), .automatic
        ])
    }

    func testBudgetAndAllSupportedEffortsRemainAvailable() {
        let capabilities = OpenRouterReasoningCapabilities(
            supportedEfforts: ["max", "custom", "none", "minimal", "medium", "low"],
            exposesEffortSelection: true, supportsMaxTokens: true
        )
        XCTAssertEqual(OpenRouterReasoningChoice.options(for: capabilities), [
            .effort("none"), .effort("minimal"), .effort("low"), .effort("medium"),
            .effort("max"), .effort("custom"), .budget, .automatic
        ])
    }

    func testMandatoryReasoningDoesNotOfferNoneOrInventUnsupportedEfforts() {
        let capabilities = OpenRouterReasoningCapabilities(
            supportedEfforts: ["none", "high"], exposesEffortSelection: true, mandatory: true
        )
        XCTAssertEqual(OpenRouterReasoningChoice.options(for: capabilities), [.effort("high"), .automatic])
    }

    func testModelWithoutEffortSelectionKeepsBudgetAndAutomatic() {
        let capabilities = OpenRouterReasoningCapabilities(supportsMaxTokens: true)
        XCTAssertEqual(OpenRouterReasoningChoice.options(for: capabilities), [.budget, .automatic])
    }

    func testNewSettingsUseExplicitEffortAndPreserveSavedAutomaticChoice() {
        var settings = AppSettings()
        XCTAssertEqual(settings.openRouterReasoningMode, "effort")
        settings.openRouterReasoningMode = "auto"
        XCTAssertEqual(settings.normalizedForPersistence().openRouterReasoningMode, "auto")
    }

    func testRepositoryUsesEffortForNewSettingsAndKeepsSavedAutomatic() throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let repository = SettingsRepository(dbQueue: database)
        var settings = try repository.load()
        XCTAssertEqual(settings.openRouterReasoningMode, "effort")

        settings.openRouterReasoningMode = "auto"
        try repository.save(settings)
        XCTAssertEqual(try repository.load().openRouterReasoningMode, "auto")
    }
}
