import SwiftUI
import MapKit

struct GenUIMapConfiguration: Identifiable {
    struct Point: Identifiable {
        let id: String
        var coordinate: CLLocationCoordinate2D?
        let title: String
        let address: String?
        let group: String?
        let query: String?

        var searchQuery: String {
            query ?? [title, address == title ? nil : address].compactMap { $0 }.joined(separator: " ")
        }
    }

    let id = UUID()
    let points: [Point]
    let origin: Point?
    let groups: [(id: String, title: String)]
    let groupsTitle: String?
    let carousel: Bool
    let fill: Bool
    let minHeight: CGFloat
    let title: String
    let narrative: String?
    let answer: String?
    let showRoute: Bool
    let optimizeStopOrder: Bool
    let travelMode: String
    let arriveBy: Date?
    let departAt: Date?

    init?(props: [String: JSONValue]) {
        func string(_ value: JSONValue?) -> String? {
            if case let .string(text) = value {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return nil
        }
        func bool(_ value: JSONValue?) -> Bool {
            if case let .bool(flag) = value { return flag }
            return false
        }
        func number(_ value: JSONValue?) -> Double? {
            if case let .number(number) = value, number.isFinite { return number }
            return nil
        }
        func point(_ value: JSONValue, index: Int) -> Point? {
            guard case let .object(object) = value else { return nil }
            let title = string(object["title"] ?? object["name"])
            let address = string(object["address"])
            let query = string(object["query"])
            var coordinate: CLLocationCoordinate2D?
            if object["lat"] != nil || object["latitude"] != nil || object["lng"] != nil || object["longitude"] != nil {
                guard let latitude = number(object["lat"] ?? object["latitude"]),
                      let longitude = number(object["lng"] ?? object["longitude"]),
                      (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
                coordinate = .init(latitude: latitude, longitude: longitude)
            }
            guard coordinate != nil || title != nil || address != nil || query != nil else { return nil }
            return Point(id: string(object["id"]) ?? "__genui_point_\(index)",
                         coordinate: coordinate,
                         title: title ?? address ?? query ?? (index < 0 ? L10n.text("出発地点") : L10n.format("地点 %d", index + 1)),
                         address: address,
                         group: string(object["group"] ?? object["group_id"]),
                         query: query)
        }
        guard case let .array(values) = props["points"], !values.isEmpty, values.count <= 100 else { return nil }
        let parsed = values.enumerated().compactMap { point($0.element, index: $0.offset) }
        guard parsed.count == values.count else { return nil }
        points = parsed
        if let value = props["origin"], value != .null {
            guard let parsedOrigin = point(value, index: -1) else { return nil }
            origin = parsedOrigin
        } else { origin = nil }
        let allPoints = (origin.map { [$0] } ?? []) + parsed
        guard Set(allPoints.map(\.id)).count == allPoints.count else { return nil }
        if case let .array(values) = props["groups"] {
            groups = values.compactMap { value in
                if case let .string(id) = value { return (id, id) }
                guard case let .object(group) = value, let id = string(group["id"]) else { return nil }
                return (id, string(group["title"] ?? group["name"]) ?? id)
            }
        } else {
            var seen = Set<String>()
            groups = parsed.compactMap { point in
                guard let group = point.group, seen.insert(group).inserted else { return nil }
                return (group, group)
            }
        }
        groupsTitle = string(props["groups_title"])
        carousel = bool(props["carousel"])
        fill = bool(props["fill"])
        minHeight = CGFloat(min(900, max(180, number(props["minHeight"]) ?? 360)))
        title = string(props["title"]) ?? L10n.text("地図")
        narrative = string(props["narrative"])
        answer = string(props["answer"])
        showRoute = bool(props["show_route"])
        optimizeStopOrder = bool(props["optimize_stop_order"])
        travelMode = string(props["travel_mode"]) ?? "driving"
        func date(_ value: JSONValue?) -> Date? {
            guard let text = string(value) else { return nil }
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions.insert(.withFractionalSeconds)
            return formatter.date(from: text)
        }
        arriveBy = date(props["arrive_by"])
        departAt = date(props["depart_at"])
        if props["arrive_by"] != nil && arriveBy == nil { return nil }
        if props["depart_at"] != nil && departAt == nil { return nil }
    }
}

@MainActor
final class GenUIMapModel: ObservableObject {
    @Published var routes: [MKRoute] = []
    @Published var status: String?
    @Published var points: [GenUIMapConfiguration.Point] = []
    @Published var origin: GenUIMapConfiguration.Point?
    @Published var failedPointIDs: Set<String> = []
    private var activeDirections: MKDirections?
    private var activeSearch: MKLocalSearch?
    private let resolve: ((String) async throws -> CLLocationCoordinate2D)?

    init(resolve: ((String) async throws -> CLLocationCoordinate2D)? = nil) {
        self.resolve = resolve
    }

    private func locate(_ point: GenUIMapConfiguration.Point) async throws -> GenUIMapConfiguration.Point {
        guard point.coordinate == nil else { return point }
        var located = point
        if let resolve {
            located.coordinate = try await resolve(point.searchQuery)
        } else {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = point.searchQuery
            let search = MKLocalSearch(request: request)
            activeSearch = search
            defer { activeSearch = nil }
            let response = try await search.start()
            guard let item = response.mapItems.first else { throw MKError(.placemarkNotFound) }
            located.coordinate = item.placemark.coordinate
        }
        try Task.checkCancellation()
        return located
    }

    func load(_ configuration: GenUIMapConfiguration) async {
        routes = []
        status = nil
        points = configuration.points
        origin = configuration.origin
        failedPointIDs = []
        let supplied = (configuration.origin.map { [$0] } ?? []) + configuration.points
        if supplied.contains(where: { $0.coordinate == nil }) {
            status = L10n.text("場所を検索しています…")
        }
        for point in supplied {
            do {
                try Task.checkCancellation()
                let located = try await locate(point)
                if point.id == configuration.origin?.id { origin = located }
                else if let index = points.firstIndex(where: { $0.id == point.id }) { points[index] = located }
            } catch {
                if Task.isCancelled || error is CancellationError { return }
                failedPointIDs.insert(point.id)
                DiagnosticsLogger.log("GenUI MapKit place search failed", level: .error, category: .network,
                                      metadata: ["pointID": point.id], error: error)
            }
        }
        guard failedPointIDs.isEmpty else {
            let titles = supplied.filter { failedPointIDs.contains($0.id) }.map(\.title).joined(separator: "、")
            status = L10n.format("場所が見つからないか、検索に失敗しました: %@", titles)
            return
        }
        status = nil
        guard !configuration.optimizeStopOrder else {
            status = L10n.text("訪問順の自動最適化には対応していません。地点の順序を指定してください。")
            return
        }
        guard configuration.showRoute else { return }
        guard ["driving", "walking", "transit"].contains(configuration.travelMode) else {
            status = L10n.text("この移動手段には対応していません。")
            return
        }
        let stops = (origin.map { [$0] } ?? []) + points
        guard stops.count > 1 else { status = L10n.text("経路には2地点以上が必要です。"); return }
        guard !(configuration.arriveBy != nil && configuration.departAt != nil) else {
            status = L10n.text("到着時刻と出発時刻は同時には指定できません。")
            return
        }
        guard stops.count <= 2 || (configuration.arriveBy == nil && configuration.departAt == nil) else {
            status = L10n.text("時刻を指定した複数区間の経路には対応していません。2地点の経路を指定してください。")
            return
        }
        status = L10n.text("経路を検索しています…")
        do {
            for index in 1..<stops.count {
                try Task.checkCancellation()
                guard let source = stops[index - 1].coordinate, let destination = stops[index].coordinate else { return }
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
                request.transportType = configuration.travelMode == "walking" ? .walking : configuration.travelMode == "transit" ? .transit : .automobile
                request.arrivalDate = configuration.arriveBy
                request.departureDate = configuration.departAt
                let directions = MKDirections(request: request)
                activeDirections = directions
                let response = try await directions.calculate()
                try Task.checkCancellation()
                guard let route = response.routes.first else {
                    status = L10n.text("この区間の経路が見つかりませんでした。")
                    return
                }
                routes.append(route)
            }
            status = L10n.format("%d区間・%.1f km", routes.count, routes.reduce(0) { $0 + $1.distance } / 1000)
        } catch {
            if Task.isCancelled { return }
            status = L10n.format("経路を取得できませんでした: %@", error.localizedDescription)
            DiagnosticsLogger.log("GenUI MapKit directions failed", level: .error, category: .network, error: error)
        }
    }

    func cancel() { activeSearch?.cancel(); activeDirections?.cancel() }
}

struct GenUIMapCanvas: View {
    let configuration: GenUIMapConfiguration
    @ObservedObject var model: GenUIMapModel
    @Binding var position: MapCameraPosition
    @Binding var selection: String?

    var body: some View {
        Map(position: $position, selection: $selection) {
            ForEach(model.points) { point in
                if let coordinate = point.coordinate {
                    Marker(point.title, coordinate: coordinate).tint(color(point)).tag(point.id)
                }
            }
            if let origin = model.origin, let coordinate = origin.coordinate {
                Marker(origin.title, systemImage: "flag.fill", coordinate: coordinate).tint(.green).tag(origin.id)
            }
            ForEach(Array(model.routes.enumerated()), id: \.offset) { _, route in
                MapPolyline(route.polyline).stroke(.teal, lineWidth: 5)
            }
        }
        .mapControls { MapCompass(); MapScaleView(); MapPitchToggle() }
        .onChange(of: model.points.compactMap(\.coordinate).count) { position = .automatic }
        .onChange(of: model.origin?.coordinate?.latitude) { position = .automatic }
        .onChange(of: model.routes.count) { position = .automatic }
    }

    private func color(_ point: GenUIMapConfiguration.Point) -> Color {
        let colors: [Color] = [.teal, .orange, .purple, .blue, .pink]
        guard let group = point.group, let index = configuration.groups.firstIndex(where: { $0.id == group }) else { return .teal }
        return colors[index % colors.count]
    }
}

struct GenUIInlineMapView: View {
    let configuration: GenUIMapConfiguration
    @StateObject private var model = GenUIMapModel()
    @State private var position: MapCameraPosition = .automatic
    @State private var selection: String?

    var body: some View {
        GenUIMapCanvas(configuration: configuration, model: model, position: $position, selection: $selection)
            .overlay(alignment: .bottomLeading) {
                if let status = model.status {
                    Text(status).font(.caption).padding(8)
                        .background(AMOLEDMaterial(material: .regularMaterial), in: RoundedRectangle(cornerRadius: 8))
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("genui-inline-map")
            .task { await model.load(configuration) }
            .onDisappear { model.cancel() }
    }
}

struct GenUIMapView: View {
    let configuration: GenUIMapConfiguration
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = GenUIMapModel()
    @State private var selection: String?
    @State private var position: MapCameraPosition = .automatic
    private let colors: [Color] = [.teal, .orange, .purple, .blue, .pink]

    private func color(_ point: GenUIMapConfiguration.Point) -> Color {
        guard let group = point.group, let index = configuration.groups.firstIndex(where: { $0.id == group }) else { return .teal }
        return colors[index % colors.count]
    }

    private func pointCard(_ point: GenUIMapConfiguration.Point) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { selection = point.id } label: { Label(point.title, systemImage: "mappin.circle.fill").foregroundStyle(color(point)) }
            if let address = point.address { Text(address).font(.caption).foregroundStyle(.secondary) }
            if model.failedPointIDs.contains(point.id) {
                Text(L10n.text("場所を取得できませんでした")).font(.caption).foregroundStyle(.secondary)
            }
            if let coordinate = point.coordinate {
                Button(L10n.text("マップで開く"), systemImage: "arrow.up.right.square") {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
                    item.name = point.title
                    item.openInMaps()
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(selection == point.id ? Color.teal.opacity(0.12) : Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GenUIMapCanvas(configuration: configuration, model: model, position: $position, selection: $selection)
                    .frame(height: max(configuration.minHeight, configuration.fill ? min(900, geometry.size.height * 0.65) : 360))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    if !configuration.groups.isEmpty {
                        if let title = configuration.groupsTitle { Text(title).font(.headline) }
                        ForEach(Array(configuration.groups.enumerated()), id: \.offset) { index, group in
                            Label { Text(group.title) } icon: { Circle().fill(colors[index % colors.count]).frame(width: 10, height: 10) }
                        }
                    }
                    if let text = configuration.narrative { Text(text) }
                    if let text = configuration.answer { Text(text).font(.headline) }
                    if let status = model.status { Text(status).font(.caption).foregroundStyle(.secondary) }
                    if configuration.carousel {
                        ScrollView(.horizontal) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach((model.origin.map { [$0] } ?? []) + model.points) { point in
                                    pointCard(point).frame(width: min(320, max(200, geometry.size.width - 48)))
                                }
                            }
                        }.scrollIndicators(.hidden)
                    } else {
                        ForEach((model.origin.map { [$0] } ?? []) + model.points) { point in pointCard(point) }
                    }
                }.padding()
            }
            }
            .navigationTitle(configuration.title)
            .toolbar(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(L10n.text("閉じる")) { dismiss() } } }
            .task { await model.load(configuration) }
            .onDisappear { model.cancel() }
        }
    }
}
