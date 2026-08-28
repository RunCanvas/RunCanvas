import SwiftUI

struct StickerCanvas: View {
    let background: CanvasBackground
    let run: Run
    @Binding var stickers: [CanvasSticker]
    @Binding var selectedStickerID: UUID?
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
                        isSelected: selectedStickerID == sticker.id,
                        isEditing: isEditing,
                        onSelect: { selectedStickerID = sticker.id },
                        onDrag: { position in
                            updateAlignmentGuides(
                                for: sticker.id,
                                at: position,
                                canvasSize: geometry.size
                            )
                        },
                        onDragEnded: { alignmentGuides = StickerAlignmentGuides() }
                    )
                }
            }
            .coordinateSpace(name: "stickerCanvas")
            .contentShape(Rectangle())
            .onTapGesture {
                if isEditing { selectedStickerID = nil }
            }
            .onPreferenceChange(StickerSizePreferenceKey.self) { stickerSizes = $0 }
        }
        .aspectRatio(4 / 5, contentMode: .fit)
        .clipped()
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

    private func updateAlignmentGuides(for stickerID: UUID, at position: CGPoint, canvasSize: CGSize) {
        guard let movingSticker = stickers.first(where: { $0.id == stickerID }) else { return }

        let contentScale = canvasSize.width / 350
        let movingSize = scaledSize(for: movingSticker, contentScale: contentScale)
        let center = CGPoint(x: position.x * canvasSize.width, y: position.y * canvasSize.height)
        let movingX = (center: center.x, leading: center.x - movingSize.width / 2, trailing: center.x + movingSize.width / 2)
        let movingY = (center: center.y, top: center.y - movingSize.height / 2, bottom: center.y + movingSize.height / 2)

        var verticalMatches = [(distance: CGFloat, coordinate: CGFloat)]()
        var horizontalMatches = [(distance: CGFloat, coordinate: CGFloat)]()
        verticalMatches.append((abs(movingX.center - canvasSize.width / 2), canvasSize.width / 2))
        horizontalMatches.append((abs(movingY.center - canvasSize.height / 2), canvasSize.height / 2))

        for other in stickers where other.id != stickerID {
            let otherSize = scaledSize(for: other, contentScale: contentScale)
            let otherCenter = CGPoint(
                x: other.position.x * canvasSize.width,
                y: other.position.y * canvasSize.height
            )
            let otherX = (
                center: otherCenter.x,
                leading: otherCenter.x - otherSize.width / 2,
                trailing: otherCenter.x + otherSize.width / 2
            )
            let otherY = (
                center: otherCenter.y,
                top: otherCenter.y - otherSize.height / 2,
                bottom: otherCenter.y + otherSize.height / 2
            )
            verticalMatches += [
                (abs(movingX.center - otherX.center), otherX.center),
                (abs(movingX.leading - otherX.leading), otherX.leading),
                (abs(movingX.trailing - otherX.trailing), otherX.trailing)
            ]
            horizontalMatches += [
                (abs(movingY.center - otherY.center), otherY.center),
                (abs(movingY.top - otherY.top), otherY.top),
                (abs(movingY.bottom - otherY.bottom), otherY.bottom)
            ]
        }

        let threshold: CGFloat = 6
        alignmentGuides.vertical = verticalMatches.min(by: { $0.distance < $1.distance })
            .flatMap { $0.distance <= threshold ? $0.coordinate : nil }
        alignmentGuides.horizontal = horizontalMatches.min(by: { $0.distance < $1.distance })
            .flatMap { $0.distance <= threshold ? $0.coordinate : nil }
    }

    private func scaledSize(for sticker: CanvasSticker, contentScale: CGFloat) -> CGSize {
        let size = stickerSizes[sticker.id] ?? CGSize(width: 100, height: 50)
        let scale = sticker.scale * contentScale
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

private struct StickerAlignmentGuides {
    var vertical: CGFloat?
    var horizontal: CGFloat?
}

private struct StickerSizePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGSize] = [:]

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
    let onDrag: (CGPoint) -> Void
    let onDragEnded: () -> Void

    @State private var dragStartPosition: CGPoint?
    @State private var resizeStartScale: CGFloat?

    private var contentScale: CGFloat {
        canvasSize.width / 350
    }

    var body: some View {
        StickerContent(sticker: sticker, run: run)
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
            .scaleEffect(sticker.scale * contentScale)
            .position(
                x: sticker.position.x * canvasSize.width,
                y: sticker.position.y * canvasSize.height
            )
            .onTapGesture { if isEditing { onSelect() } }
            .gesture(dragGesture)
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
                sticker.position = nextPosition
                onDrag(nextPosition)
            }
            .onEnded { _ in
                dragStartPosition = nil
                onDragEnded()
            }
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
        DragGesture()
            .onChanged { value in
                guard isEditing else { return }
                onSelect()
                let start = resizeStartScale ?? sticker.scale
                if resizeStartScale == nil { resizeStartScale = start }
                let diagonalDelta = (value.translation.width + value.translation.height) / 2
                sticker.scale = min(max(start + diagonalDelta / 100, 0.45), 3)
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
                        .font(.system(size: 46, weight: .black, design: fontDesign))
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
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .foregroundStyle(sticker.color)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }

    private func metricLabel(_ title: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(stickerFont(size: 30))
            Text(title)
                .font(.system(size: 10, weight: .bold, design: fontDesign))
                .tracking(1.5)
        }
    }

    private var fontDesign: Font.Design {
        switch sticker.fontStyle {
        case .bold: .default
        case .rounded: .rounded
        case .mono: .monospaced
        }
    }

    private func stickerFont(size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: fontDesign)
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
