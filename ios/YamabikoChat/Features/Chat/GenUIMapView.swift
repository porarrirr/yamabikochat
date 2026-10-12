import SwiftUI
import MapKit

struct GenUIMapConfiguration: Identifiable {
    struct Point: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let title: String
        let address: String?
        let group: String?
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
            if case let .string(text) = value { return text }
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
            guard case let .object(object) = value,
                  let latitude = number(object["lat"] ?? object["latitude"]),
                  let longitude = number(object["lng"] ?? object["longitude"]),
                  (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
            return Point(id: string(object["id"]) ?? "__genui_point_\(index)",
                         coordinate: .init(latitude: latitude, longitude: longitude),
                         title: string(object["title"] ?? object["name"]) ?? (index < 0 ? L10n.text("出発地点") : L10n.format("地点 %d", index + 1)),
                         address: string(object["address"]),
                         group: string(object["group"] ?? object["group_id"]))
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
private final class GenUIMapModel: ObservableObject {
    @Published var routes: [MKRoute] = []
    @Published var status: String?
    private var activeDirections: MKDirections?

    func load(_ configuration: GenUIMapConfiguration) async {
        routes = []
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
        let stops = (configuration.origin.map { [$0] } ?? []) + configuration.points
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
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: stops[index - 1].coordinate))
                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: stops[index].coordinate))
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

    func cancel() { activeDirections?.cancel() }
}

struct GenUIMapView: View {
    let configuration: GenUIMapConfiguration
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = GenUIMapModel()
    @State private var selection: String?
    private let colors: [Color] = [.teal, .orange, .purple, .blue, .pink]

    private func color(_ point: GenUIMapConfiguration.Point) -> Color {
        guard let group = point.group, let index = configuration.groups.firstIndex(where: { $0.id == group }) else { return .teal }
        return colors[index % colors.count]
    }

    private func pointCard(_ point: GenUIMapConfiguration.Point) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { selection = point.id } label: { Label(point.title, systemImage: "mappin.circle.fill").foregroundStyle(color(point)) }
            if let address = point.address { Text(address).font(.caption).foregroundStyle(.secondary) }
            Text("\(point.coordinate.latitude), \(point.coordinate.longitude)").font(.caption2).foregroundStyle(.secondary)
            Button(L10n.text("マップで開く"), systemImage: "arrow.up.right.square") {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: point.coordinate))
                item.name = point.title
                item.openInMaps()
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
                    Map(initialPosition: .automatic, selection: $selection) {
                        ForEach(configuration.points) { point in
                            Marker(point.title, coordinate: point.coordinate).tint(color(point)).tag(point.id)
                        }
                        if let origin = configuration.origin {
                            Marker(origin.title, systemImage: "flag.fill", coordinate: origin.coordinate).tint(.green).tag(origin.id)
                        }
                        ForEach(Array(model.routes.enumerated()), id: \.offset) { _, route in
                            MapPolyline(route.polyline).stroke(.teal, lineWidth: 5)
                        }
                    }
                    .mapControls { MapCompass(); MapScaleView(); MapPitchToggle() }
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
                                ForEach((configuration.origin.map { [$0] } ?? []) + configuration.points) { point in
                                    pointCard(point).frame(width: min(320, max(200, geometry.size.width - 48)))
                                }
                            }
                        }.scrollIndicators(.hidden)
                    } else {
                        ForEach((configuration.origin.map { [$0] } ?? []) + configuration.points) { point in pointCard(point) }
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
