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

    /// 서버 courses_path_size 제약과 같은 값. 넘으면 간격을 늘려 다시 솎는다.
    static let maxPathPoints = 5_000

    /// 기록의 경로를 코스 경로로. 좌표가 거의 안 변한 점은 버려서 크기를 줄인다(1Hz 기록은 대부분 중복).
    static func path(from route: [RoutePoint], minimumSpacing: Double = 5) -> [CoursePoint] {
        var spacing = minimumSpacing
        // 장거리 기록은 5m 간격으로도 5000점을 넘는다(25km 이상) — 넘으면 간격을 넓혀 다시 솎는다
        while true {
            var result: [CoursePoint] = []
            for point in route {
                let candidate = CoursePoint(point)
                if let last = result.last, distance(last, candidate) < spacing { continue }
                result.append(candidate)
            }
            if result.count <= maxPathPoints || spacing > 200 { return result }
            spacing *= 2
        }
    }

    // MARK: - 따라뛰기

    struct Match: Equatable {
        let index: Int
        let distanceMeters: Double
    }

    /// 직전 매칭 뒤쪽만 훑어 왕복·순환 경로의 겹친 점에서 과거 구간으로 튀지 않게 한다.
    /// 50m 넘게 떨어졌다면 코스 이탈 뒤 다른 지점으로 복귀한 것으로 보고 전체 경로에서 다시 찾는다.
    static func match(to point: CoursePoint, in path: [CoursePoint], near lastIndex: Int?,
                      window: Int = 40, fallbackDistance: Double = 50) -> Match? {
        guard !path.isEmpty else { return nil }
        guard let lastIndex else { return closestMatch(to: point, in: path.indices, path: path) }

        let start = min(max(lastIndex, path.startIndex), path.index(before: path.endIndex))
        let end = min(start + max(0, window), path.index(before: path.endIndex))
        let nearby = closestMatch(to: point, in: start...end, path: path)!
        if nearby.distanceMeters <= fallbackDistance { return nearby }
        return closestMatch(to: point, in: path.indices, path: path)
    }

    /// 코스에서 현재 위치와 가장 가까운 점의 인덱스
    static func nearestIndex(to point: CoursePoint, in path: [CoursePoint]) -> Int? {
        match(to: point, in: path, near: nil)?.index
    }

    static func nearestIndex(to point: CoursePoint, in path: [CoursePoint], near lastIndex: Int,
                             window: Int = 40, fallbackDistance: Double = 50) -> Int? {
        match(to: point, in: path, near: lastIndex,
              window: window, fallbackDistance: fallbackDistance)?.index
    }

    private static func closestMatch<Indices: Sequence>(to point: CoursePoint, in indices: Indices,
                                                        path: [CoursePoint]) -> Match?
    where Indices.Element == Int {
        var best: Match?
        var bestDistance = Double.greatestFiniteMagnitude
        for index in indices {
            let d = distance(point, path[index])
            if d < bestDistance {
                bestDistance = d
                best = Match(index: index, distanceMeters: d)
            }
        }
        return best
    }

    /// 이미 찾은 인덱스를 진행률로 바꾼다. 매칭과 이탈 거리가 같은 점을 기준으로 계산되게 분리했다.
    static func progress(through index: Int, in path: [CoursePoint]) -> Double {
        guard path.count > 1, path.indices.contains(index) else { return 0 }
        let total = length(path)
        guard total > 0 else { return 0 }
        let walked = length(Array(path[...index]))
        return min(1, max(0, walked / total))
    }

    /// 코스를 얼마나 왔는지 0…1. 가장 가까운 점까지의 누적 거리 기준이라
    /// 되돌아 뛰면 값이 줄어든다 — 그게 실제 진행 상황이다.
    static func progress(at point: CoursePoint, in path: [CoursePoint]) -> Double {
        guard let index = nearestIndex(to: point, in: path), path.count > 1 else { return 0 }
        return progress(through: index, in: path)
    }
}
