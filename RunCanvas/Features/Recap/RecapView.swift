import SwiftUI
import SwiftData
import UIKit

/// 런꾸 월말/연말 정산 — 한 달(한 해)치 러닝을 4:5 카드 한 장으로 만들어 저장·공유한다.
/// 미리보기도 저장본과 같은 이미지를 쓴다 (화면과 결과가 달라 보이지 않게).
struct RecapView: View {
    @Query private var runs: [Run]
    @State private var scope: RecapEngine.Scope = .month
    @State private var anchor: Date?
    @State private var rendered: UIImage?
    @State private var message: String?
    @State private var didSucceed = false

    init(ownerID: UUID?) {
        let owner = ownerID ?? .noOwner
        _runs = Query(filter: #Predicate<Run> { $0.ownerID == owner }, sort: \Run.startedAt, order: .reverse)
    }

    private var badgeRuns: [BadgeRun] { runs.map(\.badgeRun) }
    private var anchors: [Date] { RecapEngine.availableAnchors(runs: badgeRuns, scope: scope) }
    /// 월↔연을 바꾸면 이전에 고른 기간이 목록에 없다 — 그럴 땐 가장 최근 기간으로
    private var selected: Date? { anchors.contains(anchor ?? .distantPast) ? anchor : anchors.first }

    var body: some View {
        let recap = selected.map { RecapEngine.recap(runs: badgeRuns, scope: scope, anchor: $0) }

        ScrollView {
            VStack(spacing: 18) {
                if let recap, let selected {
                    pickers(selected)
                    preview
                    actions(recap)
                } else {
                    ContentUnavailableView("아직 기록이 없어요", systemImage: "calendar",
                                           description: Text("러닝을 한 번 기록하면 정산 카드를 만들 수 있어요"))
                        .padding(.top, 60)
                }
            }
            .padding(20)
        }
        .navigationTitle("정산 카드")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: recap) { render(recap) }
        .alert(
            didSucceed ? "저장 완료" : "저장할 수 없어요",
            isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })
        ) {
            Button("확인") {}
        } message: {
            Text(message ?? "")
        }
    }

    private func pickers(_ selected: Date) -> some View {
        VStack(spacing: 12) {
            Picker("정산", selection: $scope) {
                ForEach(RecapEngine.Scope.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("기간", selection: Binding(get: { selected }, set: { anchor = $0 })) {
                ForEach(anchors, id: \.self) { Text(RecapEngine.title(for: $0, scope: scope)).tag($0) }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let rendered {
            Image(uiImage: rendered)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
        } else {
            ProgressView("카드 만드는 중…")
                .frame(maxWidth: .infinity, minHeight: 320)
                .background(Color.card)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    @ViewBuilder
    private func actions(_ recap: RecapEngine.Recap) -> some View {
        VStack(spacing: 10) {
            PrimaryButton(title: "사진 앱에 저장", systemImage: "square.and.arrow.down") {
                Task { await saveToPhotos() }
            }
            .disabled(rendered == nil)

            if let rendered {
                ShareLink(item: Image(uiImage: rendered),
                          preview: SharePreview(recap.title, image: Image(uiImage: rendered))) {
                    Label("공유", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.card)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @MainActor
    private func render(_ recap: RecapEngine.Recap?) {
        guard let recap else { rendered = nil; return }
        let renderer = ImageRenderer(
            content: RecapCard(recap: recap, scope: scope)
                .frame(width: CanvasExporter.size.width, height: CanvasExporter.size.height)
        )
        renderer.scale = 1
        rendered = renderer.uiImage
    }

    private func saveToPhotos() async {
        guard let rendered else { return }
        do {
            try await CanvasExporter.savePNGToPhotos(rendered)
            didSucceed = true
            message = "사진 앱에 PNG로 저장했어요."
        } catch {
            didSucceed = false
            message = error.localizedDescription
        }
    }
}

/// 렌더되는 카드 그 자체 — 1080×1350 고정 좌표계로 그린다 (ImageRenderer는 화면 크기를 모른다).
/// internal인 이유: 렌더가 nil을 뱉으면 화면이 스피너에서 멈추므로 테스트가 한 번 그려 본다.
struct RecapCard: View {
    let recap: RecapEngine.Recap
    let scope: RecapEngine.Scope

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(scope.rawValue)
                .font(.system(size: 32, weight: .semibold))
                .tracking(8)
                .opacity(0.65)

            Text(recap.title)
                .font(.system(size: 78, weight: .bold))
                .padding(.top, 10)

            Spacer(minLength: 40)

            HStack(alignment: .lastTextBaseline, spacing: 14) {
                Text(RunMath.formatKm(recap.totalMeters))
                    .font(.system(size: 170, weight: .heavy))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("km")
                    .font(.system(size: 54, weight: .semibold))
                    .opacity(0.75)
            }
            Text("이 기간에 달린 거리")
                .font(.system(size: 32))
                .opacity(0.65)

            Spacer(minLength: 40)

            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(height: 2)
                .padding(.bottom, 40)

            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 38) {
                GridRow {
                    item("러닝 횟수", "\(recap.count)회")
                    item("달린 날", "\(recap.activeDays)일")
                }
                GridRow {
                    item("총 시간", RunMath.formatDuration(recap.totalSeconds))
                    item("평균 페이스", RunMath.formatPace(recap.avgPaceSecondsPerKm))
                }
                GridRow {
                    item("최장 거리", "\(RunMath.formatKm(recap.longestRunMeters)) km")
                    item("최다 요일", recap.busiestWeekday.map { "\($0)요일" } ?? "-")
                }
            }

            Spacer(minLength: 40)

            Text("RunCanvas")
                .font(.system(size: 28, weight: .semibold))
                .tracking(4)
                .opacity(0.5)
        }
        .foregroundStyle(.white)
        .padding(80)
        .frame(width: CanvasExporter.size.width, height: CanvasExporter.size.height, alignment: .topLeading)
        .background(
            LinearGradient(colors: CanvasPreset.midnight.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private func item(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 30))
                .opacity(0.6)
            Text(value)
                .font(.system(size: 54, weight: .semibold))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
