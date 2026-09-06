import SwiftUI

/// 목록 카드용 경로 썸네일. 지도 타일 없이 선만 그린다.
///
/// 카드마다 `Map`을 띄우면 타일을 받아 오느라 스크롤이 무거워지는데,
/// 목록에서 알고 싶은 건 "이 코스가 어떤 모양인가" 하나다. 지도는 상세에서 보여준다.
struct CoursePathThumbnail: View {
    let path: [CoursePoint]

    var body: some View {
        Canvas { context, size in
            guard path.count > 1,
                  let minLat = path.map(\.lat).min(), let maxLat = path.map(\.lat).max(),
                  let minLon = path.map(\.lon).min(), let maxLon = path.map(\.lon).max()
            else { return }

            // 위도 1도와 경도 1도의 실제 거리가 달라서(위도 37°에서 경도는 약 79%),
            // 그대로 그리면 코스가 옆으로 늘어난다
            let squeeze = cos((minLat + maxLat) / 2 * .pi / 180)
            let spanX = max((maxLon - minLon) * squeeze, 0.00001)
            let spanY = max(maxLat - minLat, 0.00001)

            let inset: CGFloat = 16
            let box = CGSize(width: size.width - inset * 2, height: size.height - inset * 2)
            let scale = min(box.width / spanX, box.height / spanY)
            let offset = CGPoint(x: inset + (box.width - spanX * scale) / 2,
                                 y: inset + (box.height - spanY * scale) / 2)

            func point(_ p: CoursePoint) -> CGPoint {
                CGPoint(x: offset.x + (p.lon - minLon) * squeeze * scale,
                        y: offset.y + (maxLat - p.lat) * scale)     // 위쪽이 북쪽
            }

            var line = Path()
            line.addLines(path.map(point))
            context.stroke(line, with: .color(.primary.opacity(0.8)),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

            if let start = path.first.map(point) {
                context.fill(Path(ellipseIn: CGRect(x: start.x - 4, y: start.y - 4, width: 8, height: 8)),
                             with: .color(.green))
            }
        }
        .background(Color.primary.opacity(0.04))
        .accessibilityHidden(true)      // 모양은 옆의 이름·거리로 이미 설명된다
    }
}
