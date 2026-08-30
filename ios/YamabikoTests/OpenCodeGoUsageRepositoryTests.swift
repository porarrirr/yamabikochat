import XCTest
@testable import YamabikoChat

private final class OpenCodeGoUsageHTTPClient: HTTPClientProtocol {
    private let data: Data
    private let statusCode: Int
    private var requests: [HTTPRequest] = []

    init(json: String, statusCode: Int = 200) {
        data = Data(json.utf8)
        self.statusCode = statusCode
    }

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: request.url,
            statusCode: statusCode,
            httpVersion: "HTTP/2",
            headerFields: ["Content-Type": "application/json"]
        ))
        return (data, response)
    }

    func capturedRequests() -> [HTTPRequest] { requests }
}

final class OpenCodeGoUsageRepositoryTests: XCTestCase {
    func testRetrievesOfficialUsageShapeWithBearerCredential() async throws {
        let client = OpenCodeGoUsageHTTPClient(json: Self.fixture)
        let repository = OpenCodeGoUsageRepository(
            httpClient: client
        )

        let result = await repository.retrieveUsage(apiKey: "test-opencode-go-key")

        guard case let .success(status) = result else {
            return XCTFail("Expected usage request to succeed")
        }
        XCTAssertEqual(status.rolling.usedPercent, 0)
        XCTAssertEqual(status.weekly.usedPercent, 40)
        XCTAssertEqual(status.monthly.usedPercent, 43)
        XCTAssertEqual(status.weekly.remainingPercent, 60)
        XCTAssertEqual(status.windows.map(\.period), [.rolling, .weekly, .monthly])

        let requests = client.capturedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.absoluteString, "https://opencode.ai/zen/go/v1/usage")
        XCTAssertEqual(request.headers["Accept"], "application/json")
        XCTAssertEqual(request.headers["Authorization"], "Bearer test-opencode-go-key")
        XCTAssertEqual(request.timeoutInterval, 20)
    }

    func testRejectsIncompleteUsagePayloadInsteadOfSynthesizingAWindow() async throws {
        let client = OpenCodeGoUsageHTTPClient(json: #"{"usage":{"rolling":{"status":"ok","percent":4,"resetsAt":"2026-08-13T16:27:38.287Z"},"weekly":{"status":"ok","percent":3,"resetsAt":"2026-08-17T00:00:00.287Z"}}}"#)
        let repository = OpenCodeGoUsageRepository(httpClient: client)

        guard case .failure = await repository.retrieveUsage(apiKey: "test-opencode-go-key") else {
            return XCTFail("Incomplete response must fail")
        }
    }

    func testRequiresOpenCodeGoCredentialBeforeSendingRequest() async {
        let client = OpenCodeGoUsageHTTPClient(json: Self.fixture)
        let repository = OpenCodeGoUsageRepository(httpClient: client)

        guard case .failure = await repository.retrieveUsage(apiKey: "") else {
            return XCTFail("Missing credentials must fail")
        }
        XCTAssertTrue(client.capturedRequests().isEmpty)
    }

    func testPropagatesUnauthorizedResponseInsteadOfParsingItAsUsage() async throws {
        let client = OpenCodeGoUsageHTTPClient(
            json: #"{"error":"unauthorized"}"#,
            statusCode: 401
        )
        let repository = OpenCodeGoUsageRepository(httpClient: client)

        guard case .failure = await repository.retrieveUsage(apiKey: "expired-key") else {
            return XCTFail("Unauthorized response must fail")
        }
        XCTAssertEqual(client.capturedRequests().count, 1)
    }

    func testClampsOnlyDerivedDisplayPercentages() {
        let window = OpenCodeGoUsageWindow(
            period: .monthly,
            status: "ok",
            usedPercent: 125,
            resetsAt: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(window.usedPercent, 125)
        XCTAssertEqual(window.boundedUsedPercent, 100)
        XCTAssertEqual(window.remainingPercent, 0)
    }

    private static let fixture = #"""
    {
      "usage": {
        "rolling": {
          "status": "ok",
          "percent": 0,
          "resetsAt": "2026-08-29T20:26:51.023Z"
        },
        "weekly": {
          "status": "ok",
          "percent": 40,
          "resetsAt": "2026-08-31T00:00:00.023Z"
        },
        "monthly": {
          "status": "ok",
          "percent": 43,
          "resetsAt": "2026-09-07T07:32:38.023Z"
        }
      }
    }
    """#
}
