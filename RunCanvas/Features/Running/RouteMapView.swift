import SwiftUI
import MapKit

/// 기록 경로를 지도에 그린다 (시작 초록 · 종료 빨강)
struct RouteMapView: View {
    let route: [RoutePoint]

    var body: some View {
        let coords = route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        Map(initialPosition: .automatic, interactionModes: []) {
            if coords.count > 1 {
                MapPolyline(coordinates: coords).stroke(.black, lineWidth: 4)
            }
            if let first = coords.first { Marker("시작", coordinate: first).tint(.green) }
            if coords.count > 1, let last = coords.last { Marker("종료", coordinate: last).tint(.red) }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .overlay {
            if coords.count < 2 {
                ContentUnavailableView("경로 없음", systemImage: "map", description: Text("GPS 경로가 기록되지 않았어요"))
                    .background(.regularMaterial)
            }
        }
    }
}
