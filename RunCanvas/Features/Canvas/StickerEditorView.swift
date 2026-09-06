import SwiftUI

struct StickerEditorView: View {
    /// 텍스트 스티커 최대 길이 — 캔버스 밖으로 넘치지 않게
    private static let textLimit = 30

    let background: CanvasBackground
    let run: Run
    let onBack: ([CanvasSticker]) -> Void
    let onExport: ([CanvasSticker]) -> Void

    @Environment(AuthService.self) private var auth

    @State private var stickers: [CanvasSticker]
    @State private var selectedStickerID: UUID?
    @State private var showsTextPrompt = false
    @State private var customText = ""
    @State private var editingTextStickerID: UUID?
    @State private var earnedBadges: [Badge] = []

    init(
        background: CanvasBackground,
        run: Run,
        initialStickers: [CanvasSticker],
        onBack: @escaping ([CanvasSticker]) -> Void,
        onExport: @escaping ([CanvasSticker]) -> Void
    ) {
        self.background = background
        self.run = run
        self.onBack = onBack
        self.onExport = onExport
        _stickers = State(
            initialValue: initialStickers.isEmpty
                ? Self.defaultStickers(for: run, color: background.foregroundColor)
                : initialStickers
        )
    }

    private var selectedIndex: Int? {
        guard let selectedStickerID else { return nil }
        return stickers.firstIndex { $0.id == selectedStickerID }
    }

    var body: some View {
        VStack(spacing: 0) {
            StickerCanvas(
                background: background,
                run: run,
                stickers: $stickers,
                selectedStickerID: $selectedStickerID
            )
            .padding(.horizontal, 20)
            .padding(.top, 12)

            editorControls
                .padding(.top, 12)
        }
        .navigationTitle("런꾸 3/4")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { onBack(stickers) } label: { Label("이전", systemImage: "chevron.left") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("완료") { onExport(stickers) }
                    .fontWeight(.semibold)
            }
        }
        .onAppear { loadEarnedBadges() }
        .alert(editingTextStickerID == nil ? "텍스트 추가" : "텍스트 수정", isPresented: $showsTextPrompt) {
            TextField("문구를 입력하세요", text: $customText)
            Button("취소", role: .cancel) { clearTextEditor() }
            Button(editingTextStickerID == nil ? "추가" : "수정") { saveText() }
        }
    }

    private var editorControls: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        Button("거리") { add(.distance) }
                        Button("시간") { add(.time) }
                        Button("페이스") { add(.pace) }
                        Button("날짜") { add(.date) }
                        Button("칼로리") { add(.calories) }
                        Button("심박수") { add(.heartRate) }
                        Button("경로") { add(.route) }
                    } label: { toolLabel("기록", systemImage: "plus.circle") }

                    Button { beginAddingText() } label: {
                        toolLabel("텍스트", systemImage: "textformat")
                    }

                    if !earnedBadges.isEmpty {
                        Menu {
                            ForEach(earnedBadges) { badge in
                                Button(badge.title) { add(.badge(badge)) }
                            }
                        } label: { toolLabel("뱃지", systemImage: "rosette") }
                    }

                    if selectedIndex != nil {
                        Button(role: .destructive) { deleteSelected() } label: {
                            toolLabel("삭제", systemImage: "trash")
                        }
                    }
                }
                .padding(.horizontal, 20)
            }

            if let index = selectedIndex {
                VStack(spacing: 10) {
                    HStack {
                        Text("불투명도").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $stickers[index].opacity, in: 0.2...1)
                    }
                    HStack {
                        ColorPicker("색상", selection: $stickers[index].color, supportsOpacity: false)
                        if case .text = stickers[index].kind {
                            Button("텍스트 수정") { beginEditingText(at: index) }
                                .buttonStyle(.bordered)
                        }
                    }
                    Picker("글자 스타일", selection: $stickers[index].fontStyle) {
                        ForEach(CanvasSticker.FontStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 20)
            } else {
                Text("스티커를 눌러 이동하고 모서리 핸들로 크기를 조절하세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 12)
    }

    private func toolLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color.card)
            .clipShape(Capsule())
    }

    private func add(_ kind: CanvasSticker.Kind) {
        let offset = CGFloat(stickers.count % 4) * 0.04
        let sticker = CanvasSticker(
            kind: kind,
            position: CGPoint(x: 0.5, y: 0.48 + offset),
            color: background.foregroundColor
        )
        stickers.append(sticker)
        selectedStickerID = sticker.id
    }

    /// 획득한 뱃지만 스티커로 붙일 수 있다. UserDefaults를 매 렌더에 읽지 않도록 한 번만.
    private func loadEarnedBadges() {
        guard let ownerID = auth.userID else { return }
        let dates = BadgeStore.earnedDates(for: ownerID)
        earnedBadges = Badge.allCases.filter { dates[$0] != nil }
    }

    private func deleteSelected() {
        guard let selectedStickerID else { return }
        stickers.removeAll { $0.id == selectedStickerID }
        self.selectedStickerID = nil
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
        guard !trimmed.isEmpty else {
            clearTextEditor()
            return
        }
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

    private static func defaultStickers(for run: Run, color: Color) -> [CanvasSticker] {
        var defaults = [
            CanvasSticker(kind: .distance, position: CGPoint(x: 0.5, y: 0.28), color: color),
            CanvasSticker(kind: .time, position: CGPoint(x: 0.31, y: 0.48), scale: 0.85, color: color),
            CanvasSticker(kind: .pace, position: CGPoint(x: 0.69, y: 0.48), scale: 0.85, color: color),
            CanvasSticker(kind: .date, position: CGPoint(x: 0.5, y: 0.72), scale: 0.8, color: color)
        ]
        if run.route.count > 1 {
            defaults.append(
                CanvasSticker(kind: .route, position: CGPoint(x: 0.5, y: 0.60), scale: 0.75, color: color)
            )
        }
        return defaults
    }
}
