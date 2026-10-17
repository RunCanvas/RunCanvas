import SwiftUI
import UIKit

struct StickerCanvas: View {
    let background: CanvasBackground
    let run: Run
    var canvasAspectRatio: CGFloat = 4 / 5
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
            // 가이드에 붙는 순간 손에 '톡' — 눈으로 점선을 찾지 않아도 맞았는지 안다 (놓을 때 가이드가 지워지는 건 제외)
            .sensoryFeedback(.selection, trigger: alignmentGuides) { old, new in
                (new.vertical != nil && new.vertical != old.vertical)
                    || (new.horizontal != nil && new.horizontal != old.horizontal)
            }
        }
        .aspectRatio(canvasAspectRatio, contentMode: .fit)
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
    @State private var resizeStartDistance: CGFloat?
    @State private var magnifyStartScale: CGFloat?
    @State private var rotateStartAngle: Angle?
    @State private var transformStartScale: CGFloat?
    @State private var transformStartRotation: Angle?
    @State private var transformStartDistance: CGFloat?
    @State private var transformLastTouchAngle: Double?
    @State private var transformAccumulatedRotation: Double = 0
    /// 제스처가 취소되면(제어 센터 쓸어내림·전화) onEnded 가 오지 않는다. 시작값이 남으면 다음 드래그가
    /// 취소된 자리로 튀고 실행취소 스냅샷도 안 남는다 — GestureState 는 취소 때도 되돌아가므로 이걸로 정리한다.
    @GestureState private var isTouching = false
    @GestureState private var isDraggingHandle = false

    /// 핀치와 모서리 손잡이가 같은 한계를 쓴다 — 따로 두면 핀치로 3.5배 키운 뒤 손잡이를 잡는 순간 3배로 튄다
    private static let scaleRange: ClosedRange<CGFloat> = 0.3...4
    /// 스티커 중심이 캔버스 안에 남는 범위 (정규화 좌표) — 밖으로 놓쳐 잃어버리지 않게
    private static let positionRange: ClosedRange<CGFloat> = 0.05...0.95

    private var contentScale: CGFloat {
        canvasSize.width / 350
    }

    var body: some View {
        StickerContent(sticker: sticker, run: run)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(sticker.kind.accessibilityName) 스티커")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            .gesture(
                SimultaneousGesture(SimultaneousGesture(dragGesture, magnifyGesture), rotateGesture)
                    .updating($isTouching) { _, touching, _ in touching = true }
            )
            .onChange(of: isTouching) { _, touching in
                if !touching { resetAfterTouch() }
            }
            .onChange(of: isDraggingHandle) { _, dragging in
                if !dragging { resetAfterHandleDrag() }
            }
            // 두 손가락 회전이 0°에 붙을 때만 — 새로 만든 스티커나 실행 취소로 0°가 된 건 사람이 한 동작이 아니다
            .sensoryFeedback(.selection, trigger: sticker.rotation == .zero) { _, isUpright in
                isUpright && rotateStartAngle != nil
            }
    }

    private var dragGesture: some Gesture {
        DragGesture(coordinateSpace: .named("stickerCanvas"))
            .onChanged { value in
                guard isEditing else { return }

                let start = dragStartPosition ?? sticker.position
                if dragStartPosition == nil {
                    recordUndoOnce()
                    dragStartPosition = start
                }
                // 가장자리에서 딱 멈추면 얼어붙은 것처럼 보인다 — 넘어갈수록 무겁게 따라오다가 놓으면 돌아온다
                let nextPosition = CGPoint(
                    x: (start.x + value.translation.width / canvasSize.width).rubberBanded(into: Self.positionRange),
                    y: (start.y + value.translation.height / canvasSize.height).rubberBanded(into: Self.positionRange)
                )
                sticker.position = snap(nextPosition)
            }
            .onEnded { _ in
                settleIntoCanvas()
                dragStartPosition = nil
                endGesture()
                onDragEnded()
                selectAfterGesture()
            }
    }

    /// 고무줄로 범위 밖에 나가 있던 만큼 스프링으로 돌려놓는다
    private func settleIntoCanvas() {
        let settled = CGPoint(
            x: sticker.position.x.clamped(to: Self.positionRange),
            y: sticker.position.y.clamped(to: Self.positionRange)
        )
        if settled != sticker.position {
            withAnimation(.smooth(duration: 0.3)) { sticker.position = settled }
        }
    }

    /// 선택은 손을 뗀 뒤에 — 누르는 순간 고르면 인스펙터가 올라오며 캔버스가 줄어들어,
    /// 끌고 있는 스티커가 손가락 밑에서 미끄러진다
    private func selectAfterGesture() {
        if isEditing { onSelect() }
    }

    /// 정상 종료면 각 onEnded 가 이미 비웠으니 아무 일도 없다. 취소로 남은 값만 정리한다.
    private func resetAfterTouch() {
        if dragStartPosition != nil {
            settleIntoCanvas()
            onDragEnded()
        }
        dragStartPosition = nil
        magnifyStartScale = nil
        rotateStartAngle = nil
        didRecordThisGesture = false
    }

    private func resetAfterHandleDrag() {
        resizeStartScale = nil
        resizeStartDistance = nil
        transformStartScale = nil
        transformStartRotation = nil
        transformStartDistance = nil
        transformLastTouchAngle = nil
        transformAccumulatedRotation = 0
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
                selectAfterGesture()
            }
    }

    /// 두 손가락 회전. 똑바로 세운 각도(0°) 근처에서는 살짝 붙여 준다.
    private var rotateGesture: some Gesture {
        RotateGesture()
            .onChanged { value in
                guard isEditing else { return }
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
                selectAfterGesture()
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
            .highPriorityGesture(resizeGesture.updating($isDraggingHandle) { _, dragging, _ in dragging = true })
            .accessibilityLabel("크기 조절")
            .accessibilityAdjustableAction(adjustScale)
    }

    private var transformHandle: some View {
        handleImage("rotate.right")
            .highPriorityGesture(transformGesture.updating($isDraggingHandle) { _, dragging, _ in dragging = true })
            .accessibilityLabel("회전하며 크기 조절")
            .accessibilityAdjustableAction(adjustScale)
    }

    /// VoiceOver 는 손잡이를 끌 수 없다 — 위아래 쓸기로 크기를 한 단계씩 바꾼다
    private func adjustScale(_ direction: AccessibilityAdjustmentDirection) {
        let step: CGFloat
        switch direction {
        case .increment: step = 0.1
        case .decrement: step = -0.1
        @unknown default: return
        }
        onEditBegan()
        sticker.scale = (sticker.scale + step).clamped(to: Self.scaleRange)
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
                // 왜 중심에서의 거리: 손잡이는 스티커와 함께 돈다. 화면 기준 대각선(dx+dy)으로 재면
                // 180° 돌린 스티커는 손잡이를 바깥으로 끌수록 작아지고, 90°에선 거의 안 변했다.
                let center = CGPoint(x: sticker.position.x * canvasSize.width, y: sticker.position.y * canvasSize.height)
                let distance = hypot(value.location.x - center.x, value.location.y - center.y)
                if resizeStartScale == nil {
                    onEditBegan()
                    resizeStartScale = sticker.scale
                    resizeStartDistance = max(hypot(value.startLocation.x - center.x, value.startLocation.y - center.y), 1)
                }
                let start = resizeStartScale ?? sticker.scale
                sticker.scale = (start * distance / (resizeStartDistance ?? distance)).clamped(to: Self.scaleRange)
            }
            .onEnded { _ in
                resizeStartScale = nil
                resizeStartDistance = nil
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

extension CGFloat {
    /// 범위 밖으로 나간 만큼을 점점 줄여 따라가게 한다 (iOS 스크롤 끝의 고무줄 공식).
    /// 아무리 끌어도 범위 끝에서 `dimension` 이상은 벗어나지 않는다.
    func rubberBanded(into range: ClosedRange<CGFloat>, dimension: CGFloat = 0.2, constant: CGFloat = 0.55) -> CGFloat {
        let bound = Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
        let overshoot = self - bound
        guard overshoot != 0 else { return self }
        return bound + overshoot * dimension * constant / (dimension + constant * abs(overshoot))
    }
}
