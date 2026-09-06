import SwiftUI

/// 내 기록 하나를 공유 코스로 올리는 시트. 기록 상세에서 연다.
struct CourseRegisterView: View {
    let run: Run
    let nickname: String

    @Environment(\.dismiss) private var dismiss
    @State private var service = CourseService()
    @State private var name = ""
    @State private var region = KoreaRegion.order.first ?? "서울"
    @State private var isUploading = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isUploading
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
                    LabeledContent("경로 점", value: "\(run.route.count)개")
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("등록") { upload() }
                        .disabled(!canSubmit)
                }
            }
            .overlay {
                if isUploading { ProgressView().controlSize(.large) }
            }
        }
    }

    private func upload() {
        isUploading = true
        errorMessage = nil
        Task {
            defer { isUploading = false }
            do {
                _ = try await service.register(route: run.route, name: name, region: region,
                                               ownerID: run.ownerID, ownerNickname: nickname)
                dismiss()
            } catch let error as CourseService.CourseError {
                errorMessage = error.errorDescription
            } catch {
                errorMessage = "등록하지 못했어요. 연결을 확인하고 다시 시도해 주세요."
            }
        }
    }
}
