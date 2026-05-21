import XCTest
@testable import YamabikoChat

final class SharePayloadStorageTests: XCTestCase {
    private var tempContainerURL: URL!

    override func setUp() {
        super.setUp()
        tempContainerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-storage-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempContainerURL, withIntermediateDirectories: true)
        AppGroupShareStorage.testContainerURL = tempContainerURL
    }

    override func tearDown() {
        AppGroupShareStorage.testContainerURL = nil
        try? FileManager.default.removeItem(at: tempContainerURL)
        super.tearDown()
    }

    func testWriteAndConsumeRoundTrip() {
        let payload = SharePayload(text: "hello from share", sourceApp: "Notes")
        let data = try! JSONEncoder().encode(payload)

        XCTAssertTrue(AppGroupShareStorage.writePayloadData(data))
        let consumed = AppGroupShareStorage.consumePayloadData()
        XCTAssertEqual(consumed, data)
        XCTAssertNil(AppGroupShareStorage.consumePayloadData())
    }

    func testSharePayloadPersisterUsesAppGroupFile() {
        SharePayloadPersister.save(text: "shared text", sourceApp: "Safari")

        let store = SharePayloadStore()
        let payload = store.consumeLatest()

        XCTAssertEqual(payload?.text, "shared text")
        XCTAssertEqual(payload?.sourceApp, "Safari")
    }
}
