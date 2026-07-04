import XCTest
@testable import YamabikoChat

final class ClinePassModelCatalogTests: XCTestCase {
    func testSupportedModelsIncludeRequestedCatalog() {
        let ids = ClinePassModelCatalog.supportedModels.map(\.id)
        XCTAssertEqual(ids.count, 10)
        XCTAssertTrue(ids.contains("cline-pass/glm-5.2"))
        XCTAssertTrue(ids.contains("cline-pass/qwen3.7-plus"))
    }

    func testNormalizedModelIDAddsPrefixWhenMissing() {
        XCTAssertEqual(ClinePassModelCatalog.normalizedModelID("glm-5.2"), "cline-pass/glm-5.2")
        XCTAssertEqual(ClinePassModelCatalog.normalizedModelID("cline-pass/kimi-k2.6"), "cline-pass/kimi-k2.6")
    }

    func testModelLookupAcceptsBareAndPrefixedIDs() {
        XCTAssertEqual(ClinePassModelCatalog.model(for: "glm-5.2")?.id, "cline-pass/glm-5.2")
        XCTAssertEqual(ClinePassModelCatalog.model(for: "cline-pass/deepseek-v4-pro")?.displayName, "DeepSeek V4 Pro")
    }
}