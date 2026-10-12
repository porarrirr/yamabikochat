import XCTest
@testable import YamabikoChat

final class GenUIMapTests: XCTestCase {
    private func props(_ json: String) throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8))
    }

    func testExplicitCoordinateAliasesAndMetadata() throws {
        let configuration = try XCTUnwrap(GenUIMapConfiguration(props: props(#"{"points":[{"latitude":35.6,"longitude":139.7,"name":"Tokyo","group_id":"city"}],"origin":{"lat":35,"lng":139},"groups":[{"id":"city","name":"Cities"}],"show_route":true,"travel_mode":"walking","depart_at":"2026-10-12T10:00:00Z"}"#)))
        XCTAssertEqual(configuration.points[0].coordinate.latitude, 35.6)
        XCTAssertEqual(configuration.points[0].title, "Tokyo")
        XCTAssertEqual(configuration.points[0].group, "city")
        XCTAssertEqual(configuration.groups[0].title, "Cities")
        XCTAssertNotNil(configuration.origin)
        XCTAssertNotNil(configuration.departAt)
        XCTAssertTrue(configuration.showRoute)
        XCTAssertEqual(configuration.travelMode, "walking")
    }

    func testRejectsCoordinatesRatherThanGuessingOrDroppingPoints() throws {
        for json in [
            #"{"points":[{"address":"Tokyo"}]}"#,
            #"{"points":[{"lat":91,"lng":0}]}"#,
            #"{"points":[{"lat":0,"lng":181}]}"#,
            #"{"points":[{"lat":35,"lng":139},{"name":"Missing"}]}"#,
            #"{"points":[{"lat":35,"lng":139}],"origin":{"name":"Missing"}}"#,
            #"{"points":[{"lat":35,"lng":139}],"arrive_by":"tomorrow"}"#
        ] {
            XCTAssertNil(GenUIMapConfiguration(props: try props(json)), json)
        }
    }

    func testNoRouteByDefaultAndFractionalDateSupported() throws {
        let configuration = try XCTUnwrap(GenUIMapConfiguration(props: props(#"{"points":[{"lat":35,"lng":139}],"arrive_by":"2026-10-12T10:00:00.123Z"}"#)))
        XCTAssertFalse(configuration.showRoute)
        XCTAssertFalse(configuration.optimizeStopOrder)
        XCTAssertNotNil(configuration.arriveBy)
    }

    func testPresentationPropsAndBoundedHeight() throws {
        let configuration = try XCTUnwrap(GenUIMapConfiguration(props: props(#"{"points":[{"lat":35,"lng":139}],"groups_title":"Places","carousel":true,"fill":true,"minHeight":750}"#)))
        XCTAssertEqual(configuration.groupsTitle, "Places")
        XCTAssertTrue(configuration.carousel)
        XCTAssertTrue(configuration.fill)
        XCTAssertEqual(configuration.minHeight, 750)
        for (height, expected) in [(-10, 180), (2000, 900)] {
            var values = try props(#"{"points":[{"lat":35,"lng":139}]}"#)
            values["minHeight"] = .number(Double(height))
            XCTAssertEqual(try XCTUnwrap(GenUIMapConfiguration(props: values)).minHeight, CGFloat(expected))
        }
    }

    func testRejectsDuplicatePointAndOriginIDs() throws {
        for json in [
            #"{"points":[{"id":"same","lat":35,"lng":139},{"id":"same","lat":36,"lng":140}]}"#,
            #"{"points":[{"id":"same","lat":35,"lng":139}],"origin":{"id":"same","lat":34,"lng":138}}"#
        ] {
            XCTAssertNil(GenUIMapConfiguration(props: try props(json)))
        }
        let defaults = try XCTUnwrap(GenUIMapConfiguration(props: props(#"{"points":[{"lat":35,"lng":139},{"lat":36,"lng":140}],"origin":{"lat":34,"lng":138}}"#)))
        XCTAssertEqual(Set(defaults.points.map(\.id) + [try XCTUnwrap(defaults.origin).id]).count, 3)
        XCTAssertFalse(defaults.carousel)
        XCTAssertFalse(defaults.fill)
        XCTAssertEqual(defaults.minHeight, 360)
    }
}
