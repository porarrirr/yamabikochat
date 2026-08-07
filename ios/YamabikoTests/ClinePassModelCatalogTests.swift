import XCTest
@testable import YamabikoChat

final class ClinePassModelCatalogTests: XCTestCase {
    func testSupportedModelsUseClinePassSlugs() {
        let ids = ClinePassModelCatalog.supportedModels.map(\.id)
        XCTAssertEqual(ids.count, 11)
        XCTAssertTrue(ids.contains("cline-pass/glm-5.2"))
        XCTAssertTrue(ids.contains("cline-pass/kimi-k3"))
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix("cline-pass/") })
    }

    func testNormalizedModelIDAddsClinePassPrefix() {
        XCTAssertEqual(ClinePassModelCatalog.normalizedModelID("  glm-5.2  "), "cline-pass/glm-5.2")
        XCTAssertEqual(ClinePassModelCatalog.normalizedModelID("cline-pass/kimi-k3"), "cline-pass/kimi-k3")
    }

    func testModelLookupAcceptsBareAndFullSlugs() {
        XCTAssertEqual(ClinePassModelCatalog.model(for: "glm-5.2")?.id, "cline-pass/glm-5.2")
        XCTAssertEqual(ClinePassModelCatalog.model(for: "cline-pass/kimi-k3")?.displayName, "Kimi K3")
    }
}
