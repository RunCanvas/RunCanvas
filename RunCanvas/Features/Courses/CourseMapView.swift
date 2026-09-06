import SwiftUI
import MapKit

/// 코스 경로 지도. 기록 지도(`RouteMapView`)와 달리 페이스 색이 없다 —
/// 코스에는 시각이 없고, 남의 페이스는 따라 뛰는 사람에게 의미도 없다.
struct CourseMapView: View {
    let path: [CoursePoint]
    /// 따라뛰기 중 내가 실제로 지나온 경로(있으면 코스 위에 겹쳐 그린다)
    var traveled: [RoutePoint] = []
    var isInteractive = true

    private var coordinates: [CLLocationCoordinate2D] {
        path.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }

    var body: some View {
        Map(initialPosition: .automatic, interactionModes: isInteractive ? [.pan, .zoom] : []) {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(.white, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: coordinates)
                    .stroke(Color.primary.opacity(0.75), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if traveled.count > 1 {
                MapPolyline(coordinates: traveled.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                    .stroke(.green, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let first = coordinates.first {
                Annotation("시작", coordinate: first, anchor: .center) {
                    Circle().fill(.green).frame(width: 11, height: 11)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControlVisibility(.hidden)
        .allowsHitTesting(isInteractive)
    }
}
