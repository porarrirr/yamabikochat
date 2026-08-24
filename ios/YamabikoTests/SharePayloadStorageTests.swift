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
        try! SharePayloadPersister.save(text: "shared text", sourceApp: "Safari")

        let store = SharePayloadStore()
        let payload = store.consumeLatest()

        XCTAssertEqual(payload?.text, "shared text")
        XCTAssertEqual(payload?.sourceApp, "Safari")
    }

    func testQueuePreservesMultiplePayloadsInOrder() throws {
        let oldData = Data("old".utf8)
        let newData = Data("new".utf8)
        XCTAssertTrue(AppGroupShareStorage.writePayloadData(oldData))
        XCTAssertTrue(AppGroupShareStorage.writePayloadData(newData))
        XCTAssertEqual(AppGroupShareStorage.readPayloadData(), oldData)
        XCTAssertTrue(AppGroupShareStorage.removePayloadData(matching: oldData))
        XCTAssertEqual(AppGroupShareStorage.readPayloadData(), newData)
    }

    func testIdenticalPayloadsRemainSeparateQueueEntries() throws {
        let data = Data("same".utf8)
        XCTAssertTrue(AppGroupShareStorage.writePayloadData(data))
        XCTAssertTrue(AppGroupShareStorage.writePayloadData(data))
        XCTAssertEqual(AppGroupShareStorage.consumePayloadData(), data)
        XCTAssertEqual(AppGroupShareStorage.consumePayloadData(), data)
        XCTAssertNil(AppGroupShareStorage.consumePayloadData())
    }

    func testInvalidPayloadIsQuarantinedWithoutBlockingNextPayload() throws {
        XCTAssertTrue(AppGroupShareStorage.writePayloadData(Data("invalid".utf8)))
        try SharePayloadPersister.save(text: "valid", sourceApp: nil)

        let pending = SharePayloadStore().loadLatest()

        XCTAssertEqual(pending?.payload.text, "valid")
        let failedDirectory = tempContainerURL.appendingPathComponent(
            AppGroupShareStorage.failedPayloadDirectoryName,
            isDirectory: true
        )
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: failedDirectory.path).count, 1)
    }
}
