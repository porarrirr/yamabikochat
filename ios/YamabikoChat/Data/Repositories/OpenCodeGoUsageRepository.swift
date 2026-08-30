import Foundation
import UIKit

final class OpenCodeGoUsageRepository {
    private struct UsageResponse: Decodable {
        let usage: UsagePayload
    }

    private struct UsagePayload: Decodable {
        let rolling: UsageWindowPayload
        let weekly: UsageWindowPayload
        let monthly: UsageWindowPayload
    }

    private struct UsageWindowPayload: Decodable {
        let status: String
        let percent: Double
        let resetsAt: String
    }

    private let httpClient: HTTPClientProtocol

    init(
        httpClient: HTTPClientProtocol = URLSessionHTTPClient()
    ) {
        self.httpClient = httpClient
    }

    func retrieveUsage(apiKey: String) async -> Result<OpenCodeGoUsageStatus, Error> {
        do {
            guard let apiKey = apiKey.trimmedNonEmpty else {
                throw ProviderClientError.missingCredential("OpenCode Go API key")
            }

            let request = HTTPRequest(
                url: AppConstants.defaultOpenCodeGoBaseURL.appendingPathComponent("usage"),
                method: "GET",
                headers: [
                    "Accept": "application/json",
                    "Authorization": "Bearer \(apiKey)",
                    "User-Agent": Self.userAgent
                ],
                timeoutInterval: 20
            )
            let (data, response) = try await httpClient.send(request)
            guard (200 ... 299).contains(response.statusCode) else {
                throw ProviderClientError.httpStatus(
                    response.statusCode,
                    String(data: data, encoding: .utf8) ?? ""
                )
            }
            return .success(try Self.parse(data))
        } catch {
            return .failure(error)
        }
    }

    private static func parse(_ data: Data) throws -> OpenCodeGoUsageStatus {
        let response: UsageResponse
        do {
            response = try JSONDecoder().decode(UsageResponse.self, from: data)
        } catch {
            throw ProviderClientError.parseFailure("Invalid OpenCode Go usage response: \(error.localizedDescription)")
        }

        return OpenCodeGoUsageStatus(
            rolling: try makeWindow(.rolling, response.usage.rolling),
            weekly: try makeWindow(.weekly, response.usage.weekly),
            monthly: try makeWindow(.monthly, response.usage.monthly)
        )
    }

    private static func makeWindow(
        _ period: OpenCodeGoUsagePeriod,
        _ payload: UsageWindowPayload
    ) throws -> OpenCodeGoUsageWindow {
        guard !payload.status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              payload.percent.isFinite,
              let resetsAt = parseISO8601(payload.resetsAt)
        else {
            throw ProviderClientError.parseFailure("Invalid OpenCode Go \(period.rawValue) usage window")
        }
        return OpenCodeGoUsageWindow(
            period: period,
            status: payload.status,
            usedPercent: payload.percent,
            resetsAt: resetsAt
        )
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value)
    }

    private static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let identifier = Bundle.main.bundleIdentifier ?? "com.porarri.yamabikochat.ios"
        return "YamabikoChat/\(version) (iOS \(UIDevice.current.systemVersion)) \(identifier)"
    }
}
