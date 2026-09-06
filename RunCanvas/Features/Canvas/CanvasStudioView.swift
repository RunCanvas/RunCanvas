import SwiftUI
import SwiftData

/// 런꾸 — 인스타 스토리 편집기처럼 **한 화면**에서 배경·기록·스티커·저장을 전부 한다.
/// (4단계 플로우 CanvasFlowView/BackgroundPickerView/StickerEditorView/CanvasExportView를 대체)
///
/// 디자인: 이 화면만 앱 톤(시스템 배경 + Color.card)의 예외로 **다크 크롬**을 쓴다.
/// 캔버스가 화면에서 유일하게 밝은 것이어야 색·대비를 눈으로 판단할 수 있고,
/// 사진 편집기들이 라이트 모드에서도 어두운 크롬을 쓰는 이유가 그것이다.
struct CanvasStudioView: View {
    /// 텍스트 스티커 최대 길이 — 캔버스 밖으로 넘치지 않게
    private static let textLimit = 30

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var background: CanvasBackground = .preset(.midnight)
    @State private var selectedRun: Run?
    @State private var stickers: [CanvasSticker] = []
    @State private var selection: Set<UUID> = []
    @State private var sheet: StudioSheet?
    @State private var showsTextPrompt = false
    @State private var customText = ""
    @State private var editingTextStickerID: UUID?
    @State private var earnedBadges: [Badge] = []
    @State private var didPromptForRun = false

    /// 러닝 결과 화면에서 들어오면 그 기록으로 고정된다
    private let isPresentedModally: Bool

    init(run: Run? = nil) {
        _selectedRun = State(initialValue: run)
        isPresentedModally = run != nil
    }

    private enum StudioSheet: Identifiable {
        case background, run, export
        var id: Int { hashValue }
    }

    private var selectedIndices: [Int] {
        stickers.indices.filter { selection.contains(stickers[$0].id) }
    }

    /// 여러 개를 골랐을 때 인스펙터가 보여줄 대표값 (가장 앞의 것)
    private var leadSticker: CanvasSticker? {
        selectedIndices.first.map { stickers[$0] }
    }

    /// 고른 스티커 전부에 같은 변경을 적용한다 — "선택한 것들 한 번에 색 바꾸기"
    private func applyToSelection(_ change: (inout CanvasSticker) -> Void) {
        for index in selectedIndices { change(&stickers[index]) }
    }

    var body: some View {
        ZStack {
            Studio.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                canvasArea
                bottomControls
            }
        }
        .preferredColorScheme(.dark)   // 크롬이 항상 어둡다 — 시트·키보드까지 일관되게
        .onAppear {
            loadEarnedBadges()
            promptForRunIfNeeded()
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .background:
                CanvasBackgroundSheet { background = $0; recolorDefaultStickers() }
            case .run:
                CanvasRunSheet(ownerID: auth.userID) { pick($0) }
            case .export:
                if let selectedRun {
                    CanvasExportSheet(background: background, run: selectedRun, stickers: stickers) { dismiss() }
                }
            }
        }
        .alert(editingTextStickerID == nil ? "텍스트 추가" : "텍스트 수정", isPresented: $showsTextPrompt) {
            TextField("문구를 입력하세요", text: $customText)
            Button("취소", role: .cancel) { clearTextEditor() }
            Button(editingTextStickerID == nil ? "추가" : "수정") { saveText() }
        }
    }

    // MARK: - 상단: 크롬은 최소로, 캔버스에 자리를 내준다

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Studio.surface, in: Circle())
            }
            .accessibilityLabel("닫기")
            .opacity(isPresentedModally ? 1 : 0)      // 탭에서 열면 닫을 곳이 없다
            .disabled(!isPresentedModally)

            Spacer()

            if let selectedRun {
                Button { sheet = .run } label: {
                    HStack(spacing: 5) {
                        Text("\(RunMath.formatKm(selectedRun.distanceMeters)) km")
                            .font(.system(size: 14, weight: .semibold))
                        if !isPresentedModally {
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Studio.surface, in: Capsule())
                }
                .disabled(isPresentedModally)
                .accessibilityLabel("꾸미는 기록 \(RunMath.formatKm(selectedRun.distanceMeters))킬로미터")
            }

            Spacer()

            Button { sheet = .export } label: {
                Text("저장")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(selectedRun == nil ? Studio.surface : Color.white, in: Capsule())
                    .foregroundStyle(selectedRun == nil ? Studio.dim : .black)
            }
            .disabled(selectedRun == nil)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 캔버스: 화면에서 유일하게 밝은 것

    @ViewBuilder
    private var canvasArea: some View {
        if let selectedRun {
            StickerCanvas(
                background: background,
                run: selectedRun,
                stickers: $stickers,
                selection: $selection
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: .black.opacity(0.6), radius: 24, y: 8)
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 14) {
                Image(systemName: "figure.run")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Studio.dim)
                Text("꾸밀 기록을 고르면 시작해요")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                Button("기록 고르기") { sheet = .run }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.white, in: Capsule())
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - 하단: 선택 인스펙터 + 도구

    private var bottomControls: some View {
        VStack(spacing: 14) {
            if let lead = leadSticker {
                inspector(lead: lead)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            toolRow
        }
        .animation(.snappy(duration: 0.22), value: selection)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    /// 스티커를 고르면 뜨는 줄 — 색 · 글꼴 · 투명도 · 삭제. 여러 개를 골랐으면 전부에 적용된다.
    private func inspector(lead: CanvasSticker) -> some View {
        VStack(spacing: 12) {
            if selection.count > 1 {
                Text("\(selection.count)개 선택 — 함께 바뀌어요")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Studio.dim)
            }

            // 색은 팔레트에서 고르는 게 스토리 편집기의 어휘다. 맨 끝만 커스텀 피커.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Studio.swatches, id: \.self) { color in
                        Button { applyToSelection { $0.color = color } } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                                .overlay {
                                    if lead.color == color {
                                        Circle().stroke(.white, lineWidth: 2).frame(width: 34, height: 34)
                                    }
                                }
                        }
                        .frame(width: 34, height: 34)
                        .accessibilityLabel(Studio.swatchName(color))
                    }
                    ColorPicker("", selection: Binding(
                        get: { lead.color },
                        set: { color in applyToSelection { $0.color = color } }
                    ), supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 34, height: 34)
                        .accessibilityLabel("직접 고르기")
                }
                .padding(.horizontal, 18)
            }

            HStack(spacing: 12) {
                // 글꼴은 이름표보다 실제 모양을 보여주는 게 빠르다
                ForEach(CanvasSticker.FontStyle.allCases) { style in
                    Button { applyToSelection { $0.fontStyle = style } } label: {
                        Text("Aa")
                            .font(style.sampleFont)
                            .frame(width: 42, height: 32)
                            .background(
                                lead.fontStyle == style ? Color.white : Studio.surface,
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                            .foregroundStyle(lead.fontStyle == style ? .black : .white)
                    }
                    .accessibilityLabel("\(style.rawValue) 글꼴")
                }

                Slider(value: Binding(
                    get: { lead.opacity },
                    set: { value in applyToSelection { $0.opacity = value } }
                ), in: 0.2...1)
                    .tint(.white)
                    .accessibilityLabel("불투명도")

                if selection.count == 1, case .text = lead.kind,
                   let index = selectedIndices.first {
                    iconButton("pencil", label: "텍스트 수정") { beginEditingText(at: index) }
                }
                iconButton("trash", label: "스티커 삭제") { deleteSelected() }
            }
            .padding(.horizontal, 18)
        }
    }

    private var toolRow: some View {
        HStack(spacing: 26) {
            toolButton("photo.on.rectangle", "배경") { sheet = .background }

            Menu {
                Button("거리") { add(.distance) }
                Button("시간") { add(.time) }
                Button("페이스") { add(.pace) }
                Button("날짜") { add(.date) }
                Button("칼로리") { add(.calories) }
                Button("심박수") { add(.heartRate) }
                Button("경로") { add(.route) }
            } label: {
                toolLabel("chart.bar", "기록")
            }
            .disabled(selectedRun == nil)

            toolButton("textformat", "텍스트") { beginAddingText() }
                .disabled(selectedRun == nil)

            if earnedBadges.isEmpty {
                toolButton("rosette", "뱃지") {}
                    .disabled(true)
            } else {
                Menu {
                    ForEach(earnedBadges) { badge in
                        Button(badge.title) { add(.badge(badge)) }
                    }
                } label: {
                    toolLabel("rosette", "뱃지")
                }
                .disabled(selectedRun == nil)
            }
        }
        .padding(.bottom, 4)
    }

    private func toolButton(_ systemImage: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { toolLabel(systemImage, title) }
    }

    private func toolLabel(_ systemImage: String, _ title: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 46, height: 46)
                .background(Studio.surface, in: Circle())
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(.white)
    }

    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 34)
                .background(Studio.surface, in: Circle())
                .foregroundStyle(.white)
        }
        .accessibilityLabel(label)
    }

    // MARK: - 동작

    private func promptForRunIfNeeded() {
        guard !didPromptForRun, selectedRun == nil else { return }
        didPromptForRun = true
        sheet = .run
    }

    private func pick(_ run: Run) {
        selectedRun = run
        if stickers.isEmpty {
            stickers = Self.defaultStickers(for: run, color: background.foregroundColor)
        }
    }

    private func add(_ kind: CanvasSticker.Kind) {
        let offset = CGFloat(stickers.count % 4) * 0.04
        let sticker = CanvasSticker(
            kind: kind,
            position: CGPoint(x: 0.5, y: 0.48 + offset),
            color: background.foregroundColor
        )
        stickers.append(sticker)
        selection = [sticker.id]
    }

    /// 배경을 바꾸면, 색을 따로 만진 적 없는 스티커만 새 배경 대비색을 따라가게 한다
    private func recolorDefaultStickers() {
        let newColor = background.foregroundColor
        for index in stickers.indices where stickers[index].color == .white || stickers[index].color == .black {
            stickers[index].color = newColor
        }
    }

    private func deleteSelected() {
        stickers.removeAll { selection.contains($0.id) }
        selection = []
    }

    /// 획득한 뱃지만 스티커로 붙일 수 있다. UserDefaults를 매 렌더에 읽지 않도록 한 번만.
    private func loadEarnedBadges() {
        guard let ownerID = auth.userID else { return }
        let dates = BadgeStore.earnedDates(for: ownerID)
        earnedBadges = Badge.allCases.filter { dates[$0] != nil }
    }

    private func beginAddingText() {
        editingTextStickerID = nil
        customText = ""
        showsTextPrompt = true
    }

    private func beginEditingText(at index: Int) {
        guard case .text(let text) = stickers[index].kind else { return }
        editingTextStickerID = stickers[index].id
        customText = text
        showsTextPrompt = true
    }

    private func saveText() {
        let trimmed = String(customText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.textLimit))
        guard !trimmed.isEmpty else { clearTextEditor(); return }
        if let editingTextStickerID,
           let index = stickers.firstIndex(where: { $0.id == editingTextStickerID }) {
            stickers[index].kind = .text(trimmed)
        } else {
            add(.text(trimmed))
        }
        clearTextEditor()
    }

    private func clearTextEditor() {
        editingTextStickerID = nil
        customText = ""
    }

    static func defaultStickers(for run: Run, color: Color) -> [CanvasSticker] {
        var defaults = [
            CanvasSticker(kind: .distance, position: CGPoint(x: 0.5, y: 0.28), color: color),
            CanvasSticker(kind: .time, position: CGPoint(x: 0.31, y: 0.48), scale: 0.85, color: color),
            CanvasSticker(kind: .pace, position: CGPoint(x: 0.69, y: 0.48), scale: 0.85, color: color),
            CanvasSticker(kind: .date, position: CGPoint(x: 0.5, y: 0.72), scale: 0.8, color: color)
        ]
        if run.route.count > 1 {
            defaults.append(CanvasSticker(kind: .route, position: CGPoint(x: 0.5, y: 0.60), scale: 0.75, color: color))
        }
        return defaults
    }
}

/// 편집기 전용 색 — 앱 톤과 분리해 이 화면 안에서만 쓴다
enum Studio {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.063)
    static let surface = Color.white.opacity(0.12)
    static let dim = Color.white.opacity(0.45)

    /// 스티커 색 팔레트 — 흰/검정 + 배경 프리셋에서 뽑은 색들
    static let swatches: [Color] = [
        .white,
        .black,
        Color(red: 0.96, green: 0.77, blue: 0.09),
        Color(red: 0.95, green: 0.42, blue: 0.11),
        Color(red: 0.94, green: 0.32, blue: 0.35),
        Color(red: 0.40, green: 0.66, blue: 0.35),
        Color(red: 0.20, green: 0.73, blue: 0.78),
        Color(red: 0.83, green: 0.66, blue: 0.91)
    ]

    static func swatchName(_ color: Color) -> String {
        switch color {
        case .white: "흰색"
        case .black: "검정"
        default: "색상"
        }
    }
}

#Preview {
    CanvasStudioView()
        .environment(AuthService())
        .modelContainer(for: Run.self, inMemory: true)
}
