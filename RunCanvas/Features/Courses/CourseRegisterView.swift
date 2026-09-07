import SwiftUI
import CoreLocation

/// 내 기록 하나를 공유 코스로 올리는 시트. 기록 상세에서 연다.
struct CourseRegisterView: View {
    let run: Run
    let nickname: String
    /// 등록에 성공하면 부르는 쪽이 알림을 띄운다 — 시트가 그냥 닫히면 올라갔는지 알 수 없다
    var onRegistered: ((Course) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var service = CourseService()
    @State private var name = ""
    @State private var region = KoreaRegion.order.first ?? "서울"
    @State private var isUploading = false
    @State private var didGuessRegion = false
    @State private var didPrepareRoute = false
    @State private var sharedPath: [CoursePoint] = []
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && didPrepareRoute && !sharedPath.isEmpty && !isUploading
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("코스 이름 (예: 한강 야경 5K)", text: $name)
                    Picker("지역", selection: $region) {
                        ForEach(KoreaRegion.order, id: \.self) { Text($0).tag($0) }
                    }
                } footer: {
                    Text("출발·도착 앞뒤 150m는 잘라서 올립니다. 집이나 회사 앞이 그대로 드러나지 않게 하기 위해서예요.")
                }
                .listRowBackground(Color.card)

                Section {
                    LabeledContent("기록 거리", value: String(format: "%.2f km", run.distanceKm))
                    LabeledContent(
                        "공유되는 거리",
                        value: didPrepareRoute ? String(format: "%.2f km", CourseGeometry.length(sharedPath)) : "계산 중…"
                    )
                } footer: {
                    if didPrepareRoute, sharedPath.isEmpty {
                        Text(CourseService.CourseError.tooShort.errorDescription ?? "공유할 수 있는 경로가 없어요.")
                            .foregroundStyle(.red)
                    }
                }
                .listRowBackground(Color.card)

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(Color.card)
                }
            }
            .listStyle(.insetGrouped)
            .appListTone()
            .navigationTitle("코스로 등록")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                        .disabled(isUploading)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("등록") { upload() }
                        .disabled(!canSubmit)
                }
            }
            .overlay {
                if isUploading { ProgressView().controlSize(.large) }
            }
            .interactiveDismissDisabled(isUploading)
            .task {
                sharedPath = CourseGeometry.trimmed(CourseGeometry.path(from: run.route))
                didPrepareRoute = true
                await guessRegion()
            }
        }
    }

    /// 출발 지점으로 지역을 미리 골라 둔다. 실패하면 기본값 그대로 두고 조용히 넘어간다.
    private func guessRegion() async {
        guard !didGuessRegion, let first = run.route.first else { return }
        didGuessRegion = true
        let initialRegion = region
        let location = CLLocation(latitude: first.latitude, longitude: first.longitude)
        guard let area = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "ko_KR"))
            .first?.administrativeArea,
              let guessed = KoreaRegion.short(administrativeArea: area) else { return }
        guard region == initialRegion else { return }
        region = guessed
    }

    private func upload() {
        isUploading = true
        errorMessage = nil
        Task {
            defer { isUploading = false }
            do {
                let course = try await service.register(path: sharedPath, name: name, region: region,
                                                        ownerID: run.ownerID, ownerNickname: nickname)
                onRegistered?(course)
                dismiss()
            } catch let error as CourseService.CourseError {
                errorMessage = error.errorDescription
            } catch {
                errorMessage = "등록하지 못했어요. 연결을 확인하고 다시 시도해 주세요."
            }
        }
    }
}
