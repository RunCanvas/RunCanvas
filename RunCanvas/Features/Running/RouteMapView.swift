import SwiftUI
import MapKit

/// 기록 경로 지도 — NRC 방식: 채도 낮춘 지도 위에 굵은 경로선(흰 테두리), 구간별 페이스 색(빠름 초록 → 느림 빨강), 시작·종료 점.
struct RouteMapView: View {
    let route: [RoutePoint]
    var showsLegend: Bool = true

    // 계산 프로퍼티로 두면 body가 그려질 때마다 전 경로를 다시 계산한다(마라톤이면 렌더당 수만 개 할당)
    @State private var segments: [PaceSegment] = []
    @State private var coords: [CLLocationCoordinate2D] = []

    var body: some View {
        Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
            if coords.count > 1 {
                // 흰 테두리(케이싱) → 그 위에 페이스 색 구간
                MapPolyline(coordinates: coords)
                    .stroke(.white, style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
                ForEach(segments) { segment in
                    MapPolyline(coordinates: segment.coordinates)
                        .stroke(segment.color, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                }
            }
            if let first = coords.first {
                Annotation("시작", coordinate: first, anchor: .center) { EndpointDot(color: .green) }
                    .annotationTitles(.hidden)
            }
            if coords.count > 1, let last = coords.last {
                Annotation("종료", coordinate: last, anchor: .center) { EndpointDot(color: .black) }
                    .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControlVisibility(.hidden)
        .overlay(alignment: .bottomTrailing) {   // 좌하단은 Apple 로고 자리
            if showsLegend, coords.count > 1 {
                PaceLegend()
                    .padding(10)
            }
        }
        .task(id: route.count) {
            coords = route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            segments = PaceSegment.build(from: route)
        }
        .overlay {
            if coords.count < 2 {
                ContentUnavailableView("경로 없음", systemImage: "map", description: Text("GPS 경로가 기록되지 않았어요"))
                    .background(.regularMaterial)
            }
        }
    }
}

// MARK: - 페이스 구간

/// 경로를 ~40개 구간으로 나눠 구간 평균 속도를 이 기록 안에서의 상대값(0 느림 … 1 빠름)으로 매긴다.
struct PaceSegment: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
    let relativeSpeed: Double   // 0(가장 느림) ... 1(가장 빠름)

    var color: Color { PaceSegment.color(for: relativeSpeed) }

    static func color(for t: Double) -> Color {
        // 빨강(느림) → 노랑 → 초록(빠름)
        let clamped = min(max(t, 0), 1)
        if clamped < 0.5 {
            return Color(red: 0.93, green: 0.30 + 0.55 * (clamped / 0.5), blue: 0.20)
        }
        let u = (clamped - 0.5) / 0.5
        return Color(red: 0.93 - 0.75 * u, green: 0.85 - 0.13 * u, blue: 0.20 + 0.10 * u)
    }

    static func build(from route: [RoutePoint], targetSegments: Int = 40) -> [PaceSegment] {
        guard route.count > 2 else { return [] }
        let chunk = max(route.count / targetSegments, 2)
        var raw: [(coords: [CLLocationCoordinate2D], speed: Double)] = []
        var index = 0
        while index < route.count - 1 {
            let end = min(index + chunk, route.count - 1)
            let slice = Array(route[index...end])
            var meters = 0.0
            for i in 1..<slice.count {
                let a = CLLocation(latitude: slice[i - 1].latitude, longitude: slice[i - 1].longitude)
                let b = CLLocation(latitude: slice[i].latitude, longitude: slice[i].longitude)
                meters += b.distance(from: a)
            }
            let seconds = slice.last!.timestamp.timeIntervalSince(slice.first!.timestamp)
            let speed = seconds > 0 ? meters / seconds : 0
            raw.append((slice.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }, speed))
            index = end
        }
        let speeds = raw.map(\.speed).filter { $0 > 0 }
        guard let minSpeed = speeds.min(), let maxSpeed = speeds.max(), maxSpeed > minSpeed else {
            return raw.enumerated().map { PaceSegment(id: $0.offset, coordinates: $0.element.coords, relativeSpeed: 0.75) }
        }
        return raw.enumerated().map { offset, item in
            PaceSegment(id: offset, coordinates: item.coords, relativeSpeed: (item.speed - minSpeed) / (maxSpeed - minSpeed))
        }
    }
}

// MARK: - 시작·종료 점, 범례

private struct EndpointDot: View {
    let color: Color
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}

private struct PaceLegend: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("빠름").font(.caption2).foregroundStyle(.secondary)
            LinearGradient(colors: [PaceSegment.color(for: 1), PaceSegment.color(for: 0.5), PaceSegment.color(for: 0)], startPoint: .leading, endPoint: .trailing)
                .frame(width: 60, height: 6)
                .clipShape(Capsule())
            Text("느림").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .clipShape(Capsule())
    }
}

/// 프리뷰용 샘플 경로 (구간별 속도 차이 포함)
private func sampleRoute() -> [RoutePoint] {
    let base = Date()
    var route: [RoutePoint] = []
    for i in 0..<120 {
        let t = Double(i)
        let lat: Double = 37.5445 + t * 0.00012 + sin(t / 9) * 0.0006
        let lon: Double = 127.0374 + cos(t / 11) * 0.0009
        let step: Double = (i % 30 < 15) ? 8 : 12
        route.append(RoutePoint(latitude: lat, longitude: lon, timestamp: base.addingTimeInterval(t * step)))
    }
    return route
}

#Preview {
    RouteMapView(route: sampleRoute())
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding()
}
