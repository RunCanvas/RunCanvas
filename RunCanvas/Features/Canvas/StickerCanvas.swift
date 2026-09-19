import SwiftUI
import UIKit

struct StickerCanvas: View {
    let background: CanvasBackground
    let run: Run
    @Binding var stickers: [CanvasSticker]
    /// 여러 개를 함께 고를 수 있다 (길게 눌러 추가)
    @Binding var selection: Set<UUID>
    var isEditing = true
    var isRotationMode = false
    var onDeleteSticker: ((UUID) -> Void)? = nil
    var onEditTextSticker: ((UUID) -> Void)? = nil
    var onEditBegan: (() -> Void)? = nil

    @State private var stickerSizes: [UUID: CGSize] = [:]
    @State private var alignmentGuides = StickerAlignmentGuides()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Group {
                    if background.isTransparent, isEditing {
                        TransparencyGrid()
                    } else {
                        CanvasBackgroundView(background: background)
                    }
                }
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
                        isRotationMode: isRotationMode,
                        // 이미 골라 둔 것이면 유지한다 — 제스처가 매 onChanged 마다 이걸 부르므로,
                        // 통째로 갈아치우면 여러 개 선택해 둔 상태에서 하나만 건드려도 선택이 하나로 줄어
                        // "함께 바꾸기"가 사라진다.
                        onSelect: { if !selection.contains(sticker.id) { selection = [sticker.id] } },
                        onToggleSelect: {
                            if selection.contains(sticker.id) { selection.remove(sticker.id) }
                            else { selection.insert(sticker.id) }
                        },
                        snap: { position in
                            snapped(position, movingID: sticker.id, canvasSize: geometry.size)
                        },
                        onDragEnded: { alignmentGuides = StickerAlignmentGuides() },
                        onDelete: { onDeleteSticker?(sticker.id) },
                        onEditText: { onEditTextSticker?(sticker.id) },
                        onEditBegan: { onEditBegan?() }
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
    let isRotationMode: Bool
    let onSelect: () -> Void
    /// 길게 누르면 선택에 넣고 뺀다 (여러 개 함께 고르기)
    let onToggleSelect: () -> Void
    /// 드래그 위치를 정렬 가이드에 스냅해서 돌려준다
    let snap: (CGPoint) -> CGPoint
    let onDragEnded: () -> Void
    let onDelete: () -> Void
    let onEditText: () -> Void
    let onEditBegan: () -> Void

    /// 한 제스처 동작에 실행취소 스냅샷을 한 번만 남기기 위한 표시 (recordUndoOnce 참고)
    @State private var didRecordThisGesture = false
    @State private var dragStartPosition: CGPoint?
    @State private var resizeStartScale: CGFloat?
    @State private var magnifyStartScale: CGFloat?
    @State private var rotateStartAngle: Angle?
    @State private var transformStartScale: CGFloat?
    @State private var transformStartRotation: Angle?
    @State private var transformStartDistance: CGFloat?
    @State private var transformLastTouchAngle: Double?
    @State private var transformAccumulatedRotation: Double = 0

    /// 핀치와 모서리 손잡이가 같은 한계를 쓴다 — 따로 두면 핀치로 3.5배 키운 뒤 손잡이를 잡는 순간 3배로 튄다
    private static let scaleRange: ClosedRange<CGFloat> = 0.3...4

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
            // maximumDistance 기본값 10pt 는 DragGesture 의 minimumDistance 와 같아서,
            // 손가락을 얹고 잠깐 멈췄다 끄는 흔한 동작에서 롱프레스가 먼저 발동해 선택이 풀렸다가
            // 드래그가 시작되며 다시 켜진다(인스펙터 깜빡임, 회전 모드가 저절로 꺼짐).
            .onLongPressGesture(minimumDuration: 0.35, maximumDistance: 2) { if isEditing { onToggleSelect() } }
            // 인스타 스토리처럼 스티커 위에서 바로 옮기고(한 손가락) 키우고 돌린다(두 손가락)
            .gesture(SimultaneousGesture(SimultaneousGesture(dragGesture, magnifyGesture), rotateGesture))
    }

    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .named("stickerCanvas"))
            .onChanged { value in
                guard isEditing else { return }
                onSelect()

                let start = dragStartPosition ?? sticker.position
                if dragStartPosition == nil {
                    recordUndoOnce()
                    dragStartPosition = start
                }
                let nextPosition = CGPoint(
                    x: min(max(start.x + value.translation.width / canvasSize.width, 0.05), 0.95),
                    y: min(max(start.y + value.translation.height / canvasSize.height, 0.05), 0.95)
                )
                sticker.position = snap(nextPosition)
            }
            .onEnded { _ in
                dragStartPosition = nil
                endGesture()
                onDragEnded()
            }
    }

    /// 세 제스처(드래그·확대·회전)는 동시 인식이라 두 손가락으로 확대하며 살짝 돌리면 전부 시작된다.
    /// 각자 onEditBegan 을 부르면 한 동작에 실행취소 스냅샷이 2~3칸 쌓여, 되돌리기를 눌러도
    /// 화면이 안 바뀌다가 갑자기 두 편집 전으로 점프한다. 한 동작에 한 번만 기록한다.
    private func recordUndoOnce() {
        guard !didRecordThisGesture else { return }
        didRecordThisGesture = true
        onEditBegan()
    }

    /// 세 제스처가 모두 끝났을 때만 다음 동작을 위해 연다
    private func endGesture() {
        if dragStartPosition == nil, magnifyStartScale == nil, rotateStartAngle == nil {
            didRecordThisGesture = false
        }
    }

    /// 두 손가락 확대·축소. 핸들 드래그보다 이쪽이 주 조작이다.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard isEditing else { return }
                onSelect()
                let start = magnifyStartScale ?? sticker.scale
                if magnifyStartScale == nil {
                    recordUndoOnce()
                    magnifyStartScale = start
                }
                sticker.scale = (start * value.magnification).clamped(to: Self.scaleRange)
            }
            .onEnded { _ in
                magnifyStartScale = nil
                endGesture()
            }
    }

    /// 두 손가락 회전. 똑바로 세운 각도(0°) 근처에서는 살짝 붙여 준다.
    private var rotateGesture: some Gesture {
        RotateGesture()
            .onChanged { value in
                guard isEditing else { return }
                onSelect()
                let start = rotateStartAngle ?? sticker.rotation
                if rotateStartAngle == nil {
                    recordUndoOnce()
                    rotateStartAngle = start
                }
                let next = start + value.rotation
                // 왜: truncatingRemainder는 부호를 남겨 반대로 한 바퀴 돌린 358°가 -2°로 안 잡히므로 360° 쪽도 함께 본다
                let remainder = abs(next.degrees.truncatingRemainder(dividingBy: 360))
                sticker.rotation = (remainder < 4 || remainder > 356) ? .zero : next
            }
            .onEnded { _ in
                rotateStartAngle = nil
                endGesture()
            }
    }

    private var resizeOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.white, style: StrokeStyle(lineWidth: 1.5, dash: [5]))

            VStack {
                HStack {
                    overlayButton("xmark", label: "스티커 삭제", role: .destructive, action: onDelete)
                    Spacer()
                    if isTextSticker {
                        overlayButton("pencil", label: "텍스트 수정", action: onEditText)
                    }
                }
                .offset(y: -16)

                Spacer()

                HStack {
                    Spacer()
                    if isRotationMode {
                        transformHandle
                    } else {
                        resizeHandle
                    }
                }
            }
        }
    }

    private var resizeHandle: some View {
        handleImage("arrow.up.left.and.arrow.down.right")
            .highPriorityGesture(resizeGesture)
            .accessibilityLabel("크기 조절")
    }

    private var transformHandle: some View {
        handleImage("rotate.right")
            .highPriorityGesture(transformGesture)
            .accessibilityLabel("회전하며 크기 조절")
    }

    /// 손잡이는 `.overlay` 라 아래의 `.scaleEffect(sticker.scale * contentScale)` 를 같이 탄다.
    /// 역보정하지 않으면 기본 배치(scale 0.72)에서도 22pt, 하한 0.3 까지 줄이면 9pt 가 돼
    /// 캔버스 위에서 삭제·텍스트 수정이 사실상 불가능하다.
    private var handleScale: CGFloat { 1 / max(sticker.scale * contentScale, 0.001) }

    private func handleImage(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 30, height: 30)
            .background(.white, in: Circle())
            .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            .frame(width: 44, height: 44)   // 보이는 크기는 30 그대로, 터치 영역만 hit-target 44
            .contentShape(Circle())
            .scaleEffect(handleScale)
            .offset(x: 14, y: 14)
    }

    private var isTextSticker: Bool {
        if case .text = sticker.kind { return true }
        return false
    }

    private func overlayButton(
        _ systemImage: String,
        label: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(role == .destructive ? .white : .black)
                .frame(width: 30, height: 30)
                .background(role == .destructive ? Color.red : Color.white, in: Circle())
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                .frame(width: 44, height: 44)   // 보이는 크기는 30 그대로, 터치 영역만 hit-target 44
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(handleScale)               // handleImage 와 같은 이유 — 스티커 배율을 되돌린다
        .accessibilityLabel(label)
    }

    private var resizeGesture: some Gesture {
        // 드래그와 같은 캔버스 좌표계 — 기본(local) 좌표계는 scaleEffect를 타서 스케일이 커질수록 둔해진다
        DragGesture(coordinateSpace: .named("stickerCanvas"))
            .onChanged { value in
                guard isEditing else { return }
                onSelect()
                let start = resizeStartScale ?? sticker.scale
                if resizeStartScale == nil {
                    onEditBegan()
                    resizeStartScale = start
                }
                let diagonalDelta = (value.translation.width + value.translation.height) / 2
                // 기준 350pt 캔버스에서 100pt = 스케일 1 — 기기 폭이 달라도 손맛이 같게
                sticker.scale = (start + diagonalDelta / (canvasSize.width / 3.5)).clamped(to: Self.scaleRange)
            }
            .onEnded { _ in
                resizeStartScale = nil
            }
    }

    /// 중심에서의 거리와 각도를 함께 반영해 한 번의 드래그로 크기와 회전을 조절한다.
    /// 짧은 각도 차이를 누적하므로 -180°/180° 경계에서도 회전이 튀지 않는다.
    private var transformGesture: some Gesture {
        DragGesture(coordinateSpace: .named("stickerCanvas"))
            .onChanged { value in
                guard isEditing else { return }
                onSelect()

                let center = CGPoint(
                    x: sticker.position.x * canvasSize.width,
                    y: sticker.position.y * canvasSize.height
                )
                let startVector = CGVector(
                    dx: value.startLocation.x - center.x,
                    dy: value.startLocation.y - center.y
                )
                let currentVector = CGVector(
                    dx: value.location.x - center.x,
                    dy: value.location.y - center.y
                )
                let currentDistance = hypot(currentVector.dx, currentVector.dy)
                let currentTouchAngle = atan2(currentVector.dy, currentVector.dx)

                if transformStartScale == nil {
                    onEditBegan()
                    transformStartScale = sticker.scale
                    transformStartRotation = sticker.rotation
                    transformStartDistance = max(hypot(startVector.dx, startVector.dy), 1)
                    transformLastTouchAngle = atan2(startVector.dy, startVector.dx)
                    transformAccumulatedRotation = 0
                }

                if let lastTouchAngle = transformLastTouchAngle {
                    let rawDelta = currentTouchAngle - lastTouchAngle
                    transformAccumulatedRotation += atan2(sin(rawDelta), cos(rawDelta))
                }
                transformLastTouchAngle = currentTouchAngle

                let baseScale = transformStartScale ?? sticker.scale
                let baseDistance = transformStartDistance ?? currentDistance
                sticker.scale = (baseScale * currentDistance / max(baseDistance, 1))
                    .clamped(to: Self.scaleRange)
                sticker.rotation = (transformStartRotation ?? sticker.rotation)
                    + .radians(transformAccumulatedRotation)
            }
            .onEnded { _ in
                transformStartScale = nil
                transformStartRotation = nil
                transformStartDistance = nil
                transformLastTouchAngle = nil
                transformAccumulatedRotation = 0
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
                // 왜: 사진 앱에 저장되는 결과물이라 기기 언어와 상관없이 한국어로 고정한다
                Text(run.startedAt.formatted(.dateTime.year().month(.wide).day().locale(Locale(identifier: "ko_KR"))))
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
            case .image(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageStickerSize(image).width, height: imageStickerSize(image).height)
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

    private func imageStickerSize(_ image: UIImage) -> CGSize {
        let maxSide: CGFloat = 180
        guard image.size.width > 0, image.size.height > 0 else {
            return CGSize(width: maxSide, height: maxSide)
        }
        let ratio = min(maxSide / image.size.width, maxSide / image.size.height)
        return CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
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

        // 왜: 축마다 따로 늘리면 정사각형 코스가 직사각형이 되고 남북 직선은 경도 잡음이 폭 전체로 커진다.
        // 경도는 위도에 따라 짧아지므로(cos φ) 보정한 뒤 한 배율로 가운데에 그려 RouteMapView와 같은 모양을 유지한다.
        let lonScale = cos((minLat + maxLat) / 2 * .pi / 180)
        let width = (maxLon - minLon) * lonScale
        let height = maxLat - minLat
        let inset = rect.insetBy(dx: 6, dy: 6)
        let scale = min(inset.width / max(width, 0.000_001), inset.height / max(height, 0.000_001))
        let originX = inset.midX - width * scale / 2
        let originY = inset.midY + height * scale / 2
        var path = Path()

        for (index, point) in route.enumerated() {
            let x = originX + (point.longitude - minLon) * lonScale * scale
            let y = originY - (point.latitude - minLat) * scale
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
            else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        return path
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
