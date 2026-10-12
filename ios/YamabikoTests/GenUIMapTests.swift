import XCTest
import MapKit
@testable import YamabikoChat

final class GenUIMapTests: XCTestCase {
    private func props(_ json: String) throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: Data(json.utf8))
    }

    func testInlineMapFramesRejectInvalidDimensions() {
        XCTAssertEqual(GenUIHostPolicy.mapFrame(from: ["x": 12, "y": 450, "width": 320, "height": 260]),
                       CGRect(x: 12, y: 450, width: 320, height: 260))
        XCTAssertNotNil(GenUIHostPolicy.mapFrame(from: ["x": -10, "y": 0, "width": 0, "height": 0]))
        for frame in [
            ["x": 0, "y": 0, "width": -1, "height": 260],
            ["x": 0, "y": 0, "width": 320, "height": 901],
            ["x": Double.infinity, "y": 0, "width": 320, "height": 260],
            ["x": 0, "width": 320, "height": 260]
        ] {
            XCTAssertNil(GenUIHostPolicy.mapFrame(from: frame))
        }
    }

    func testExplicitCoordinateAliasesAndMetadata() throws {
        let configuration = try XCTUnwrap(GenUIMapConfiguration(props: props(#"{"points":[{"latitude":35.6,"longitude":139.7,"name":"Tokyo","group_id":"city"}],"origin":{"lat":35,"lng":139},"groups":[{"id":"city","name":"Cities"}],"show_route":true,"travel_mode":"walking","depart_at":"2026-10-12T10:00:00Z"}"#)))
        XCTAssertEqual(configuration.points[0].coordinate?.latitude, 35.6)
        XCTAssertEqual(configuration.points[0].title, "Tokyo")
        XCTAssertEqual(configuration.points[0].group, "city")
        XCTAssertEqual(configuration.groups[0].title, "Cities")
        XCTAssertNotNil(configuration.origin)
        XCTAssertNotNil(configuration.departAt)
        XCTAssertTrue(configuration.showRoute)
        XCTAssertEqual(configuration.travelMode, "walking")
    }

    func testRejectsInvalidCoordinatesAndEmptyLocations() throws {
        for json in [
            #"{"points":[{"address":"  "}]}"#,
            #"{"points":[{"lat":91,"lng":0}]}"#,
            #"{"points":[{"lat":0,"lng":181}]}"#,
            #"{"points":[{"lat":35,"lng":139},{}]}"#,
            #"{"points":[{"lat":35,"lng":139}],"origin":{}}"#,
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

    func testPlaceNamesAddressesQueriesAndOriginWithoutCoordinates() throws {
        let configuration = try XCTUnwrap(GenUIMapConfiguration(props: props(#"{"points":[{"name":"東京駅","address":"東京都千代田区"},{"address":"大阪市北区"},{"query":"京都駅"}],"origin":{"title":"品川駅"}}"#)))
        XCTAssertTrue(configuration.points.allSatisfy { $0.coordinate == nil })
        XCTAssertEqual(configuration.points[0].searchQuery, "東京駅 東京都千代田区")
        XCTAssertEqual(configuration.points[2].searchQuery, "京都駅")
        XCTAssertEqual(configuration.points[1].searchQuery, "大阪市北区")
        XCTAssertEqual(configuration.origin?.searchQuery, "品川駅")
        XCTAssertNotNil(configuration.origin)
    }

    @MainActor
    func testResolvesOnlyMissingCoordinatesAndPreservesIdentity() async throws {
        let configuration = try XCTUnwrap(GenUIMapConfiguration(props: props(#"{"points":[{"id":"station","name":"東京駅","group":"city"},{"id":"known","lat":36,"lng":140}],"origin":{"id":"start","address":"品川駅"}}"#)))
        var queries: [String] = []
        let model = GenUIMapModel(resolve: { query in
            queries.append(query)
            return .init(latitude: 35, longitude: 139)
        })
        await model.load(configuration)
        XCTAssertEqual(queries.count, 2)
        XCTAssertTrue(queries.contains("東京駅"))
        XCTAssertEqual(model.points.map(\.id), ["station", "known"])
        XCTAssertEqual(model.points[0].group, "city")
        XCTAssertEqual(model.points[0].coordinate?.latitude, 35)
        XCTAssertEqual(model.points[1].coordinate?.latitude, 36)
        XCTAssertEqual(model.origin?.coordinate?.longitude, 139)
        XCTAssertTrue(model.failedPointIDs.isEmpty)
        XCTAssertNil(model.status)
        XCTAssertTrue(model.routes.isEmpty)
    }

    @MainActor
    func testFailedSearchKeepsPointAndStopsRoute() async throws {
        let configuration = try XCTUnwrap(GenUIMapConfiguration(props: props(#"{"points":[{"id":"missing","name":"見つからない場所"},{"lat":35,"lng":139}],"show_route":true}"#)))
        let model = GenUIMapModel(resolve: { _ in throw MKError(.placemarkNotFound) })
        await model.load(configuration)
        XCTAssertEqual(model.points.count, 2)
        XCTAssertNil(model.points[0].coordinate)
        XCTAssertEqual(model.failedPointIDs, ["missing"])
        XCTAssertNotNil(model.status)
        XCTAssertTrue(model.routes.isEmpty)
    }

    @MainActor
    func testCancellationDoesNotPublishSearchFailure() async throws {
        let configuration = try XCTUnwrap(GenUIMapConfiguration(props: props(#"{"points":[{"name":"東京駅"}]}"#)))
        let model = GenUIMapModel(resolve: { _ in throw CancellationError() })
        await model.load(configuration)
        XCTAssertTrue(model.failedPointIDs.isEmpty)
        XCTAssertNil(model.points[0].coordinate)
    }

}
