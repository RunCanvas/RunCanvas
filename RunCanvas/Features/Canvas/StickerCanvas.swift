import SwiftUI

struct StickerCanvas: View {
    let background: CanvasBackground
    let run: Run
    @Binding var stickers: [CanvasSticker]
    /// 여러 개를 함께 고를 수 있다 (길게 눌러 추가)
    @Binding var selection: Set<UUID>
    var isEditing = true

    @State private var stickerSizes: [UUID: CGSize] = [:]
    @State private var alignmentGuides = StickerAlignmentGuides()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CanvasBackgroundView(background: background)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                alignmentGuideView(in: geometry.size)

                ForEach($stickers) { $sticker in
                    StickerLayer(
                        sticker: $sticker,
                        run: run,
                        canvasSize: geometry.size,
                        isSelected: selection.contains(sticker.id),
                        isEditing: isEditing,
                        onSelect: { selection = [sticker.id] },
                        onToggleSelect: {
                            if selection.contains(sticker.id) { selection.remove(sticker.id) }
                            else { selection.insert(sticker.id) }
                        },
                        snap: { position in
                            snapped(position, movingID: sticker.id, canvasSize: geometry.size)
                        },
                        onDragEnded: { alignmentGuides = StickerAlignmentGuides() }
                    )
                }
            }
            .coordinateSpace(.named("stickerCanvas"))
            .contentShape(Rectangle())
            .onTapGesture {
                if isEditing { selection = [] }
            }
            .onPreferenceChange(StickerSizePreferenceKey.self) { stickerSizes = $0 }
        }
        .aspectRatio(4 / 5, contentMode: .fit)
        .clipped()
        // 편집 화면과 ImageRenderer 결과의 글자 크기를 같게 (렌더러는 기본 환경으로 그린다)
        .dynamicTypeSize(.large)
    }

    @ViewBuilder
    private func alignmentGuideView(in size: CGSize) -> some View {
        if isEditing, let x = alignmentGuides.vertical {
            Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            .stroke(.white.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .shadow(color: .black.opacity(0.5), radius: 1)
            .allowsHitTesting(false)
        }
        if isEditing, let y = alignmentGuides.horizontal {
            Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            .stroke(.white.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            .shadow(color: .black.opacity(0.5), radius: 1)
            .allowsHitTesting(false)
        }
    }

    /// 드래그 중인 스티커를 캔버스 중앙·다른 스티커의 중심/모서리에 맞추고(스냅), 맞은 선을 가이드로 남긴다.
    /// 돌려주는 값은 스냅이 적용된 0...1 정규화 좌표.
    private func snapped(_ position: CGPoint, movingID: UUID, canvasSize: CGSize) -> CGPoint {
        guard let moving = stickers.first(where: { $0.id == movingID }) else { return position }

        let contentScale = canvasSize.width / 350
        let movingSize = scaledSize(for: moving, contentScale: contentScale)
        let center = CGPoint(x: position.x * canvasSize.width, y: position.y * canvasSize.height)
        let halfWidth = movingSize.width / 2
        let halfHeight = movingSize.height / 2

        // (가이드로 그릴 좌표, 거기에 맞추려면 스티커 중심이 있어야 할 좌표)
        var verticals = [(guide: canvasSize.width / 2, center: canvasSize.width / 2)]
        var horizontals = [(guide: canvasSize.height / 2, center: canvasSize.height / 2)]

        for other in stickers where other.id != movingID {
            let otherSize = scaledSize(for: other, contentScale: contentScale)
            let otherCenter = CGPoint(
                x: other.position.x * canvasSize.width,
                y: other.position.y * canvasSize.height
            )
            let otherHalfWidth = otherSize.width / 2
            let otherHalfHeight = otherSize.height / 2
            verticals += [
                (guide: otherCenter.x, center: otherCenter.x),
                (guide: otherCenter.x - otherHalfWidth, center: otherCenter.x - otherHalfWidth + halfWidth),
                (guide: otherCenter.x + otherHalfWidth, center: otherCenter.x + otherHalfWidth - halfWidth)
            ]
            horizontals += [
                (guide: otherCenter.y, center: otherCenter.y),
                (guide: otherCenter.y - otherHalfHeight, center: otherCenter.y - otherHalfHeight + halfHeight),
                (guide: otherCenter.y + otherHalfHeight, center: otherCenter.y + otherHalfHeight - halfHeight)
            ]
        }

        let threshold = 8 * contentScale
        let vertical = verticals.min { abs($0.center - center.x) < abs($1.center - center.x) }
            .flatMap { abs($0.center - center.x) <= threshold ? $0 : nil }
        let horizontal = horizontals.min { abs($0.center - center.y) < abs($1.center - center.y) }
            .flatMap { abs($0.center - center.y) <= threshold ? $0 : nil }

        // 매 프레임 @State를 쓰면 스티커 전부가 다시 그려지므로 값이 바뀔 때만
        let guides = StickerAlignmentGuides(vertical: vertical?.guide, horizontal: horizontal?.guide)
        if guides != alignmentGuides { alignmentGuides = guides }

        return CGPoint(
            x: (vertical?.center ?? center.x) / canvasSize.width,
            y: (horizontal?.center ?? center.y) / canvasSize.height
        )
    }

    private func scaledSize(for sticker: CanvasSticker, contentScale: CGFloat) -> CGSize {
        let size = stickerSizes[sticker.id] ?? CGSize(width: 100, height: 50)
        let scale = sticker.scale * contentScale
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

private struct StickerAlignmentGuides: Equatable {
    var vertical: CGFloat?
    var horizontal: CGFloat?
}

private struct StickerSizePreferenceKey: PreferenceKey {
    static let defaultValue: [UUID: CGSize] = [:]

    static func reduce(value: inout [UUID: CGSize], nextValue: () -> [UUID: CGSize]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct StickerLayer: View {
    @Binding var sticker: CanvasSticker
    let run: Run
    let canvasSize: CGSize
    let isSelected: Bool
    let isEditing: Bool
    let onSelect: () -> Void
    /// 길게 누르면 선택에 넣고 뺀다 (여러 개 함께 고르기)
    let onToggleSelect: () -> Void
    /// 드래그 위치를 정렬 가이드에 스냅해서 돌려준다
    let snap: (CGPoint) -> CGPoint
    let onDragEnded: () -> Void

    @State private var dragStartPosition: CGPoint?
    @State private var resizeStartScale: CGFloat?
    @State private var magnifyStartScale: CGFloat?
    @State private var rotateStartAngle: Angle?

    private var contentScale: CGFloat {
        canvasSize.width / 350
    }

    var body: some View {
        StickerContent(sticker: sticker, run: run)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(sticker.kind.accessibilityName) 스티커")
            .padding(8)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: StickerSizePreferenceKey.self,
                        value: [sticker.id: proxy.size]
                    )
                }
            }
            .overlay {
                if isEditing && isSelected {
                    resizeOverlay
                }
            }
            .background {
                if isEditing && isSelected {
                    RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.18))
                }
            }
            .opacity(sticker.opacity)
            .rotationEffect(sticker.rotation)
            .scaleEffect(sticker.scale * contentScale)
            .position(
                x: sticker.position.x * canvasSize.width,
                y: sticker.position.y * canvasSize.height
            )
            .onTapGesture { if isEditing { onSelect() } }
            .onLongPressGesture(minimumDuration: 0.35) { if isEditing { onToggleSelect() } }
            // 인스타 스토리처럼 스티커 위에서 바로 옮기고(한 손가락) 키우고 돌린다(두 손가락)
            .gesture(SimultaneousGesture(SimultaneousGesture(dragGesture, magnifyGesture), rotateGesture))
    }

    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .named("stickerCanvas"))
            .onChanged { value in
                guard isEditing else { return }
                onSelect()
                let start = dragStartPosition ?? sticker.position
                if dragStartPosition == nil { dragStartPosition = start }
                let nextPosition = CGPoint(
                    x: min(max(start.x + value.translation.width / canvasSize.width, 0.05), 0.95),
                    y: min(max(start.y + value.translation.height / canvasSize.height, 0.05), 0.95)
                )
                sticker.position = snap(nextPosition)
            }
            .onEnded { _ in
                dragStartPosition = nil
                onDragEnded()
            }
    }

    /// 두 손가락 확대·축소. 핸들 드래그보다 이쪽이 주 조작이다.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard isEditing else { return }
                onSelect()
                let start = magnifyStartScale ?? sticker.scale
                if magnifyStartScale == nil { magnifyStartScale = start }
                sticker.scale = min(max(start * value.magnification, 0.3), 4)
            }
            .onEnded { _ in magnifyStartScale = nil }
    }

    /// 두 손가락 회전. 똑바로 세운 각도(0°) 근처에서는 살짝 붙여 준다.
    private var rotateGesture: some Gesture {
        RotateGesture()
            .onChanged { value in
                guard isEditing else { return }
                onSelect()
                let start = rotateStartAngle ?? sticker.rotation
                if rotateStartAngle == nil { rotateStartAngle = start }
                let next = start + value.rotation
                sticker.rotation = abs(next.degrees.truncatingRemainder(dividingBy: 360)) < 4 ? .zero : next
            }
            .onEnded { _ in rotateStartAngle = nil }
    }

    private var resizeOverlay: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white, style: StrokeStyle(lineWidth: 1.5, dash: [5]))

            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 30, height: 30)
                .background(.white, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .offset(x: 14, y: 14)
                .contentShape(Circle())
                .highPriorityGesture(resizeGesture)
                .accessibilityLabel("크기 조절")
        }
    }

    private var resizeGesture: some Gesture {
        // 드래그와 같은 캔버스 좌표계 — 기본(local) 좌표계는 scaleEffect를 타서 스케일이 커질수록 둔해진다
        DragGesture(coordinateSpace: .named("stickerCanvas"))
            .onChanged { value in
                guard isEditing else { return }
                onSelect()
                let start = resizeStartScale ?? sticker.scale
                if resizeStartScale == nil { resizeStartScale = start }
                let diagonalDelta = (value.translation.width + value.translation.height) / 2
                // 기준 350pt 캔버스에서 100pt = 스케일 1 — 기기 폭이 달라도 손맛이 같게
                sticker.scale = min(max(start + diagonalDelta / (canvasSize.width / 3.5), 0.45), 3)
            }
            .onEnded { _ in
                resizeStartScale = nil
            }
    }
}

private struct StickerContent: View {
    let sticker: CanvasSticker
    let run: Run

    var body: some View {
        Group {
            switch sticker.kind {
            case .distance:
                VStack(spacing: -2) {
                    Text(RunMath.formatKm(run.distanceMeters))
                        .font(.system(size: 46, weight: sticker.fontStyle.weight, design: fontDesign))
                        .tracking(sticker.fontStyle.tracking)
                    Text("KILOMETERS")
                        .font(.system(size: 11, weight: .bold, design: fontDesign))
                        .tracking(2)
                }
            case .time:
                metricLabel("TIME", RunMath.formatDuration(run.movingSeconds))
            case .pace:
                metricLabel("PACE /KM", RunMath.formatPace(run.paceSecondsPerKm))
            case .date:
                Text(run.startedAt.formatted(.dateTime.year().month(.wide).day()))
                    .font(stickerFont(size: 22))
            case .calories:
                metricLabel("KCAL", "\(Int(run.calories.rounded()))")
            case .heartRate:
                metricLabel("AVG BPM", run.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "--")
            case .route:
                RouteStickerShape(route: run.route)
                    .stroke(sticker.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                    .frame(width: 190, height: 125)
                    .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
            case .badge(let badge):
                VStack(spacing: 4) {
                    BadgeArt(badge: badge, isEarned: true, size: 78)
                        .colorMultiply(sticker.color)
                    Text(badge.title).font(.caption.bold())
                }
            case .text(let text):
                Text(text)
                    .font(stickerFont(size: 30))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)   // 기준 350pt 캔버스를 넘지 않게 줄바꿈
            }
        }
        .fixedSize(horizontal: !isWrappingText, vertical: true)
        .foregroundStyle(sticker.color)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }

    /// 텍스트만 가로 폭을 고정하지 않고 줄바꿈시킨다
    private var isWrappingText: Bool {
        if case .text = sticker.kind { return true }
        return false
    }

    private func metricLabel(_ title: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(stickerFont(size: 30))
            Text(title)
                .font(.system(size: 10, weight: .bold, design: fontDesign))
                .tracking(1.5)
        }
    }

    private var fontDesign: Font.Design { sticker.fontStyle.design }

    private func stickerFont(size: CGFloat) -> Font {
        .system(size: size, weight: sticker.fontStyle.weight, design: fontDesign)
    }
}

private struct RouteStickerShape: Shape {
    let route: [RoutePoint]

    func path(in rect: CGRect) -> Path {
        guard route.count > 1,
              let minLat = route.map(\.latitude).min(),
              let maxLat = route.map(\.latitude).max(),
              let minLon = route.map(\.longitude).min(),
              let maxLon = route.map(\.longitude).max() else { return Path() }

        let latSpan = max(maxLat - minLat, 0.000_001)
        let lonSpan = max(maxLon - minLon, 0.000_001)
        let inset = rect.insetBy(dx: 6, dy: 6)
        var path = Path()

        for (index, point) in route.enumerated() {
            let x = inset.minX + ((point.longitude - minLon) / lonSpan) * inset.width
            let y = inset.maxY - ((point.latitude - minLat) / latSpan) * inset.height
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}
