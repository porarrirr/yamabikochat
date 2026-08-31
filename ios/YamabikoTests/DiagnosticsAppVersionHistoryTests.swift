import Foundation
import XCTest
@testable import YamabikoChat

final class DiagnosticsAppVersionHistoryTests: XCTestCase {
    func testFirstLaunchStoresVersionWithoutReportingUpdate() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var reportedPreviousVersion: DiagnosticsAppVersion?

        DiagnosticsAppVersionHistory.recordLaunch(
            current: DiagnosticsAppVersion(version: "1.0.0", build: "1"),
            defaults: defaults
        ) { reportedPreviousVersion = $0 }

        XCTAssertNil(reportedPreviousVersion)

        DiagnosticsAppVersionHistory.recordLaunch(
            current: DiagnosticsAppVersion(version: "1.0.0", build: "1"),
            defaults: defaults
        ) { reportedPreviousVersion = $0 }
        XCTAssertNil(reportedPreviousVersion)
    }

    func testVersionUpdateReportsPreviousVersionOnlyOnce() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let oldVersion = DiagnosticsAppVersion(version: "1.0.0", build: "1")
        let newVersion = DiagnosticsAppVersion(version: "2.0.0", build: "2")
        var reportedPreviousVersions: [DiagnosticsAppVersion] = []

        DiagnosticsAppVersionHistory.recordLaunch(current: oldVersion, defaults: defaults) { _ in }
        DiagnosticsAppVersionHistory.recordLaunch(current: newVersion, defaults: defaults) {
            reportedPreviousVersions.append($0)
        }
        DiagnosticsAppVersionHistory.recordLaunch(current: newVersion, defaults: defaults) {
            reportedPreviousVersions.append($0)
        }

        XCTAssertEqual(reportedPreviousVersions, [oldVersion])
    }

    func testBuildUpdateReportsPreviousBuild() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let oldVersion = DiagnosticsAppVersion(version: "1.0.0", build: "1")
        let newVersion = DiagnosticsAppVersion(version: "1.0.0", build: "2")
        var reportedPreviousVersion: DiagnosticsAppVersion?

        DiagnosticsAppVersionHistory.recordLaunch(current: oldVersion, defaults: defaults) { _ in }
        DiagnosticsAppVersionHistory.recordLaunch(current: newVersion, defaults: defaults) {
            reportedPreviousVersion = $0
        }

        XCTAssertEqual(reportedPreviousVersion, oldVersion)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "DiagnosticsAppVersionHistoryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
