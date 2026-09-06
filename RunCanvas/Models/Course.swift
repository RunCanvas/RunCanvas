import Foundation
import CoreLocation

/// 사용자가 올려 공유하는 러닝 코스. 서버 `courses` 한 행이 그대로 이 모양이다.
///
/// 등록 시각은 담지 않는다 — 목록 정렬은 서버가 하고, 화면에 쓸 데가 없는데
/// timestamptz 파싱만 또 하나 늘어난다(`RunDTO`에서 이미 겪은 함정).
struct Course: Identifiable, Codable, Equatable {
    let id: UUID
    let ownerID: UUID
    let ownerNickname: String
    let name: String
    let region: String
    let distanceMeters: Double
    let path: [CoursePoint]

    private enum CodingKeys: String, CodingKey {
        case id, name, region, path
        case ownerID = "owner_id"
        case ownerNickname = "owner_nickname"
        case distanceMeters = "distance_m"
    }

    init(id: UUID = UUID(), ownerID: UUID, ownerNickname: String, name: String,
         region: String, distanceMeters: Double, path: [CoursePoint]) {
        self.id = id
        self.ownerID = ownerID
        self.ownerNickname = ownerNickname
        self.name = name
        self.region = region
        self.distanceMeters = distanceMeters
        self.path = path
    }

    var distanceKm: Double { distanceMeters / 1000 }
    var coordinates: [CLLocationCoordinate2D] {
        path.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
    }
}

/// 코스 경로의 한 점. 러닝 기록(`RoutePoint`)과 달리 시각은 버린다 —
/// 남이 따라 뛸 때 필요한 건 선 모양이지, 원래 주인이 몇 시에 지났는지가 아니다.
struct CoursePoint: Codable, Equatable, Hashable {
    var lat: Double
    var lon: Double

    init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    init(_ point: RoutePoint) {
        self.init(lat: point.latitude, lon: point.longitude)
    }
}
