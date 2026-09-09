import SwiftUI
import SwiftData
import PhotosUI
import UIKit

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

    /// 설정에서 미리 정해 둔 기록 기본 색 (빈 값이면 "배경에 맞춤")
    @AppStorage(CanvasTheme.storageKey) private var stickerColorHex = ""

    @State private var background: CanvasBackground = .preset(.midnight)
    @State private var selectedRun: Run?
    @State private var stickers: [CanvasSticker] = []
    @State private var selection: Set<UUID> = []
    @State private var sheet: StudioSheet?
    @State private var showsTextPrompt = false
    @State private var customText = ""
    @State private var editingTextStickerID: UUID?
    @State private var imageItem: PhotosPickerItem?
    @State private var isLoadingImage = false
    @State private var imageErrorMessage: String?
    @State private var undoStack: [CanvasEditSnapshot] = []
    @State private var isRotationMode = false
    @State private var didPromptForRun = false
    @State private var showsDiscardConfirmation = false
    @State private var didSave = false

    /// 러닝 결과 화면에서 들어오면 그 기록으로 고정된다 (런꾸 탭에서 열면 기록을 고를 수 있다)
    private let hasFixedRun: Bool

    init(run: Run? = nil) {
        _selectedRun = State(initialValue: run)
        hasFixedRun = run != nil
    }

    private enum StudioSheet: Identifiable {
        case background, run, export
        var id: Int { hashValue }
    }

    private struct CanvasEditSnapshot {
        let background: CanvasBackground
        let stickers: [CanvasSticker]
    }

    private var selectedIndices: [Int] {
        stickers.indices.filter { selection.contains(stickers[$0].id) }
    }

    /// 여러 개를 골랐을 때 인스펙터가 보여줄 대표값 (가장 앞의 것)
    private var leadSticker: CanvasSticker? {
        selectedIndices.first.map { stickers[$0] }
    }

    /// 새로 붙이는 스티커·기본 배치가 쓸 색 — 테마 색이 배경에 묻히면 배경 대비색으로 물러난다
    private var defaultStickerColor: Color {
        CanvasTheme.resolvedColor(hex: stickerColorHex, background: background)
    }

    /// 고른 스티커 전부에 같은 변경을 적용한다 — "선택한 것들 한 번에 색 바꾸기"
    private func applyToSelection(recordUndo: Bool = true, _ change: (inout CanvasSticker) -> Void) {
        if recordUndo { rememberState() }
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
            promptForRunIfNeeded()
        }
        .sheet(item: $sheet) { which in
            switch which {
            case .background:
                CanvasBackgroundSheet { changeBackground(to: $0) }
            case .run:
                CanvasRunSheet(ownerID: auth.userID) { pick($0) }
            case .export:
                if let selectedRun {
                    CanvasExportSheet(
                        background: background,
                        run: selectedRun,
                        stickers: stickers,
                        onSaved: { didSave = true },
                        onSavedToApp: { dismiss() }
                    )
                }
            }
        }
        .confirmationDialog("꾸미던 내용을 버릴까요?", isPresented: $showsDiscardConfirmation, titleVisibility: .visible) {
            Button("버리고 나가기", role: .destructive) { dismiss() }
            Button("계속 꾸미기", role: .cancel) {}
        } message: {
            Text("저장하지 않은 스티커 배치는 남지 않아요.")
        }
        .alert(editingTextStickerID == nil ? "텍스트 추가" : "텍스트 수정", isPresented: $showsTextPrompt) {
            // 왜: saveText 가 넘치는 글자를 소리 없이 자르므로 한도를 미리 보여 준다
            TextField("문구 (\(Self.textLimit)자까지)", text: $customText)
            Button("취소", role: .cancel) { clearTextEditor() }
            Button(editingTextStickerID == nil ? "추가" : "수정") { saveText() }
        }
        .alert("이미지를 추가할 수 없어요", isPresented: Binding(
            get: { imageErrorMessage != nil },
            set: { if !$0 { imageErrorMessage = nil } }
        )) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(imageErrorMessage ?? "")
        }
        .onChange(of: imageItem) { _, item in
            guard let item, !isLoadingImage else { return }
            loadImageSticker(from: item)
        }
        .onChange(of: selection) { _, selection in
            if selection.isEmpty { isRotationMode = false }
        }
    }

    // MARK: - 상단: 크롬은 최소로, 캔버스에 자리를 내준다

    private var topBar: some View {
        HStack {
            Button { goBack() } label: {
                Label("뒤로", systemImage: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Studio.surface, in: Capsule())
                    .hitTarget()
            }


            Button { undoLastEdit() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Studio.surface, in: Circle())
                    .foregroundStyle(undoStack.isEmpty ? Studio.dim : .white)
                    .hitTarget()
            }
            .disabled(undoStack.isEmpty)
            .accessibilityLabel("실행 취소")

            Spacer()

            if let selectedRun {
                // 왜: 고정 기록은 정보 표시다 — disabled 버튼으로 두면 흐려져 "눌러야 하는데 안 되는 것"으로 보인다
                if hasFixedRun {
                    runChip(selectedRun)
                } else {
                    Button { sheet = .run } label: { runChip(selectedRun).hitTarget() }
                }
            }

            Spacer()

            Button { sheet = .export } label: {
                Text("저장")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(selectedRun == nil ? Studio.surface : Color.white, in: Capsule())
                    .foregroundStyle(selectedRun == nil ? Studio.dim : .black)
                    .hitTarget()
            }
            .disabled(selectedRun == nil)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 3)   // 왜: 히트 영역을 44pt로 키운 만큼 줄여 상단 높이(≈50pt)를 예전 그대로 둔다
    }

    private func runChip(_ run: Run) -> some View {
        HStack(spacing: 5) {
            Text("\(RunMath.formatKm(run.distanceMeters)) km")
                .font(.system(size: 14, weight: .semibold))
            if !hasFixedRun {
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Studio.surface, in: Capsule())
        .accessibilityLabel("꾸미는 기록 \(RunMath.formatKm(run.distanceMeters))킬로미터")
    }

    // MARK: - 캔버스: 화면에서 유일하게 밝은 것

    @ViewBuilder
    private var canvasArea: some View {
        if let selectedRun {
            StickerCanvas(
                background: background,
                run: selectedRun,
                stickers: $stickers,
                selection: $selection,
                isRotationMode: isRotationMode,
                onDeleteSticker: { deleteSticker(id: $0) },
                onEditTextSticker: { beginEditingText(id: $0) },
                onEditBegan: { rememberState() }
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
                // 왜 spacing 0: 44pt 히트 영역 안에 34pt 링이 들어가 있어 시각 간격은 예전(10pt) 그대로다
                HStack(spacing: 0) {
                    ForEach(Studio.swatches, id: \.name) { swatch in
                        let isOn = Studio.isSame(lead.color, swatch.color)
                        Button { applyToSelection { $0.color = swatch.color } } label: {
                            Circle()
                                .fill(swatch.color)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().stroke(.white.opacity(0.35), lineWidth: 1))
                                .overlay {
                                    if isOn {
                                        Circle().stroke(.white, lineWidth: 2).frame(width: 34, height: 34)
                                    }
                                }
                                .hitTarget()
                        }
                        .accessibilityLabel(swatch.name)
                        .accessibilityAddTraits(isOn ? [.isSelected] : [])
                    }
                    ColorPicker("", selection: Binding(
                        get: { lead.color },
                        set: { color in applyToSelection(recordUndo: false) { $0.color = color } }
                    ), supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("직접 고르기")
                        .simultaneousGesture(TapGesture().onEnded { rememberState() })
                }
                .padding(.horizontal, 18)
            }

            HStack(spacing: 12) {
                // 글꼴은 이름표보다 실제 모양을 보여주는 게 빠르다
                ForEach(CanvasSticker.FontStyle.allCases) { style in
                    let isOn = lead.fontStyle == style
                    Button { applyToSelection { $0.fontStyle = style } } label: {
                        Text("Aa")
                            .font(style.sampleFont)
                            .frame(width: 42, height: 32)
                            .background(isOn ? Color.white : Studio.surface, in: RoundedRectangle(cornerRadius: 9))
                            .foregroundStyle(isOn ? .black : .white)
                            .hitTarget()
                    }
                    .accessibilityLabel("\(style.rawValue) 글꼴")
                    .accessibilityAddTraits(isOn ? [.isSelected] : [])
                }

                Spacer()

                if selection.count == 1, case .text = lead.kind,
                   let index = selectedIndices.first {
                    iconButton("pencil", label: "텍스트 수정") { beginEditingText(at: index) }
                }
                iconButton(
                    "rotate.right",
                    label: isRotationMode ? "회전 모드 끄기" : "회전 모드 켜기",
                    isOn: isRotationMode
                ) {
                    isRotationMode.toggle()
                }
                iconButton("trash", label: "스티커 삭제") { deleteSelected() }
            }
            .padding(.horizontal, 18)

            // 왜 별도 줄: 글꼴·삭제와 한 줄에 두면 SE(375pt)에서 슬라이더 이동 거리가 45pt밖에 안 남아 두세 단계밖에 못 잡는다
            HStack(spacing: 12) {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Studio.dim)
                Slider(value: Binding(
                    get: { lead.opacity },
                    set: { value in applyToSelection(recordUndo: false) { $0.opacity = value } }
                ), in: 0.2...1, onEditingChanged: { editing in
                    if editing { rememberState() }
                })
                    .tint(.white)
                    .accessibilityLabel("불투명도")
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
                // 왜: 없는 데이터는 "--"·빈 경로 스티커가 되어 공유 이미지에 그대로 박힌다 (defaultStickers 와 같은 가드)
                if selectedRun?.averageHeartRate != nil {
                    Button("심박수") { add(.heartRate) }
                }
                if (selectedRun?.route.count ?? 0) > 1 {
                    Button("경로") { add(.route) }
                }
            } label: {
                toolLabel("chart.bar", "기록")
            }
            .disabled(selectedRun == nil)

            toolButton("textformat", "텍스트") { beginAddingText() }
                .disabled(selectedRun == nil)

            PhotosPicker(selection: $imageItem, matching: .images, preferredItemEncoding: .compatible) {
                toolLabel(isLoadingImage ? "hourglass" : "photo.badge.plus", isLoadingImage ? "불러오는 중" : "이미지")
            }
            .disabled(selectedRun == nil || isLoadingImage)
            .accessibilityLabel(isLoadingImage ? "이미지 불러오는 중" : "이미지 추가")
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

    private func iconButton(
        _ systemImage: String,
        label: String,
        isOn: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 34, height: 34)
                .background(isOn ? Color.white : Studio.surface, in: Circle())
                .foregroundStyle(isOn ? .black : .white)
                .hitTarget()
        }
        .accessibilityLabel(label)
    }

    // MARK: - 동작

    /// 저장한 적 없이 꾸미던 중이면 한 번 물어본다 (인스타가 하는 방식)
    private func goBack() {
        if selectedRun != nil && !didSave {
            showsDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    /// 왜: 결과 화면·갤러리에서 기록이 고정돼 들어와도 시트에서 고른 것과 같은 기본 배치로 시작해야 한다
    /// (예전엔 selectedRun 이 있으면 바로 빠져나가 빈 캔버스가 떴다)
    private func promptForRunIfNeeded() {
        guard !didPromptForRun else { return }
        didPromptForRun = true
        if let selectedRun { pick(selectedRun) } else { sheet = .run }
    }

    private func pick(_ run: Run) {
        selectedRun = run
        if stickers.isEmpty {
            stickers = Self.defaultStickers(for: run, color: defaultStickerColor)
        }
    }

    private func add(_ kind: CanvasSticker.Kind) {
        rememberState()
        let offset = CGFloat(stickers.count % 4) * 0.04
        let sticker = CanvasSticker(
            kind: kind,
            position: CGPoint(x: 0.5, y: 0.48 + offset),
            color: defaultStickerColor
        )
        stickers.append(sticker)
        selection = [sticker.id]
    }

    /// 배경을 바꾸면, 아직 기본 색 그대로인 스티커만 새 기본 색을 따라가게 한다.
    /// 색을 직접 고른 스티커는 건드리지 않는다 — 기준이 "흰/검정"에서 "바뀌기 전 기본 색"으로 바뀌었을 뿐,
    /// 테마가 "배경에 맞춤"이면 그 기본 색이 곧 흰/검정이라 예전 동작 그대로다.
    private func changeBackground(to newBackground: CanvasBackground) {
        rememberState()
        let previous = defaultStickerColor
        background = newBackground
        let current = defaultStickerColor
        guard !Studio.isSame(previous, current) else { return }
        for index in stickers.indices where Studio.isSame(stickers[index].color, previous) {
            stickers[index].color = current
        }
    }

    private func deleteSelected() {
        guard !selection.isEmpty else { return }
        rememberState()
        stickers.removeAll { selection.contains($0.id) }
        selection = []
    }

    private func deleteSticker(id: UUID) {
        guard stickers.contains(where: { $0.id == id }) else { return }
        rememberState()
        stickers.removeAll { $0.id == id }
        selection.remove(id)
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

    private func beginEditingText(id: UUID) {
        guard let index = stickers.firstIndex(where: { $0.id == id }) else { return }
        beginEditingText(at: index)
    }

    private func loadImageSticker(from item: PhotosPickerItem) {
        isLoadingImage = true
        Task {
            defer {
                isLoadingImage = false
                imageItem = nil
            }
            do {
                guard let data = try await withTimeoutValue(
                    seconds: 20,
                    { try await item.loadTransferable(type: Data.self) }
                ), let image = UIImage(data: data) else {
                    imageErrorMessage = "사진을 불러오지 못했어요."
                    return
                }
                add(.image(await downsampledStickerImage(image)))
            } catch {
                imageErrorMessage = "사진을 불러오지 못했어요. 다른 사진으로 시도해 주세요."
            }
        }
    }

    private func downsampledStickerImage(_ image: UIImage) async -> UIImage {
        let maxSide: CGFloat = 1_600
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let ratio = maxSide / longest
        let target = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
        return await image.byPreparingThumbnail(ofSize: target) ?? image
    }

    private func saveText() {
        let trimmed = String(customText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.textLimit))
        guard !trimmed.isEmpty else { clearTextEditor(); return }
        if let editingTextStickerID,
           let index = stickers.firstIndex(where: { $0.id == editingTextStickerID }) {
            rememberState()
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

    private func rememberState() {
        undoStack.append(CanvasEditSnapshot(background: background, stickers: stickers))
        if undoStack.count > 30 { undoStack.removeFirst(undoStack.count - 30) }
    }

    private func undoLastEdit() {
        guard let previous = undoStack.popLast() else { return }
        background = previous.background
        stickers = previous.stickers
        selection = []
        isRotationMode = false
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

    /// 스티커 색 팔레트 — 흰/검정 + 배경 프리셋에서 뽑은 색들.
    /// 왜 hex 로 만드나: 설정 테마(`CanvasTheme.presets`)와 같은 값을 가져야 선택 링·기본 색 판정이 맞는다
    /// (예전엔 0.96 리터럴 vs 245/255 라 `==` 가 늘 false 였다).
    static let swatches: [(name: String, color: Color)] = [
        ("흰색", "FFFFFF"), ("검정", "000000"), ("옐로", "F5C417"), ("오렌지", "F26B1C"),
        ("코랄", "F0525A"), ("그린", "66A859"), ("민트", "33BAC7"), ("라벤더", "D4A8E8")
    ].compactMap { name, hex in CanvasTheme.color(hex: hex).map { color in (name: name, color: color) } }

    /// `Color ==` 는 `.white` 와 rgb(1,1,1) 처럼 만든 경로가 다르면 못 알아본다 — 저장 규칙과 같은 hex 6자리로 비교
    static func isSame(_ a: Color, _ b: Color) -> Bool {
        CanvasTheme.hex(a) == CanvasTheme.hex(b)
    }
}

private extension View {
    /// 보이는 크기는 두고 터치 영역만 44pt로 — 스티커를 끌다가 바로 누르는 버튼들이라 빗나가기 쉽다
    func hitTarget() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
}

#Preview {
    CanvasStudioView()
        .environment(AuthService())
        .modelContainer(for: Run.self, inMemory: true)
}
