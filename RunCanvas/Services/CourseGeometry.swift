import Foundation

/// 코스 경로 계산. 전부 순수 함수라 유닛 테스트로 검증한다.
/// 지도·CoreLocation 없이 도는 게 목적 — 거리 계산은 하버사인으로 직접 한다.
enum CourseGeometry {
    /// 지구 반지름(m)
    private static let earthRadius = 6_371_000.0

    /// 두 점 사이 거리(m)
    static func distance(_ a: CoursePoint, _ b: CoursePoint) -> Double {
        let lat1 = a.lat * .pi / 180, lat2 = b.lat * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.lon - a.lon) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * atan2(sqrt(h), sqrt(max(0, 1 - h)))
    }

    /// 경로 전체 길이(m)
    static func length(_ path: [CoursePoint]) -> Double {
        guard path.count > 1 else { return 0 }
        return zip(path, path.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    /// 앞뒤를 잘라낸 경로. 러닝은 대개 집·직장 문 앞에서 시작하고 끝나므로,
    /// 그대로 올리면 코스를 공유하는 게 아니라 사는 곳을 공유하는 셈이 된다.
    /// 자르고 남은 길이가 `minimumLength` 미만이면 공유하기엔 너무 짧다고 보고 빈 배열.
    static func trimmed(_ path: [CoursePoint], byMeters trim: Double = 150,
                        minimumLength: Double = 300) -> [CoursePoint] {
        guard path.count > 1 else { return [] }

        var start = 0
        var walked = 0.0
        while start + 1 < path.count, walked < trim {
            walked += distance(path[start], path[start + 1])
            start += 1
        }

        var end = path.count - 1
        walked = 0
        while end - 1 > start, walked < trim {
            walked += distance(path[end], path[end - 1])
            end -= 1
        }

        guard end > start else { return [] }
        let kept = Array(path[start...end])
        return length(kept) >= minimumLength ? kept : []
    }

    /// 기록의 경로를 코스 경로로. 좌표가 거의 안 변한 점은 버려서 크기를 줄인다(1Hz 기록은 대부분 중복).
    static func path(from route: [RoutePoint], minimumSpacing: Double = 5) -> [CoursePoint] {
        var result: [CoursePoint] = []
        for point in route {
            let candidate = CoursePoint(point)
            if let last = result.last, distance(last, candidate) < minimumSpacing { continue }
            result.append(candidate)
        }
        return result
    }

    // MARK: - 따라뛰기

    /// 코스에서 현재 위치와 가장 가까운 점의 인덱스
    static func nearestIndex(to point: CoursePoint, in path: [CoursePoint]) -> Int? {
        guard !path.isEmpty else { return nil }
        var best = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, candidate) in path.enumerated() {
            let d = distance(point, candidate)
            if d < bestDistance {
                bestDistance = d
                best = index
            }
        }
        return best
    }

    /// 코스를 얼마나 왔는지 0…1. 가장 가까운 점까지의 누적 거리 기준이라
    /// 되돌아 뛰면 값이 줄어든다 — 그게 실제 진행 상황이다.
    static func progress(at point: CoursePoint, in path: [CoursePoint]) -> Double {
        guard let index = nearestIndex(to: point, in: path), path.count > 1 else { return 0 }
        let total = length(path)
        guard total > 0 else { return 0 }
        let walked = length(Array(path[0...index]))
        return min(1, max(0, walked / total))
    }

    /// 코스에서 얼마나 벗어났는지(m). 가장 가까운 점까지의 직선 거리.
    static func offCourseMeters(_ point: CoursePoint, path: [CoursePoint]) -> Double {
        guard let index = nearestIndex(to: point, in: path) else { return 0 }
        return distance(point, path[index])
    }
}
