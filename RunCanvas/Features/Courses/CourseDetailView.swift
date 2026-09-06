import SwiftUI

/// 코스 하나 — 지도, 길이, 올린 사람, 그리고 따라뛰기.
struct CourseDetailView: View {
    let course: Course
    let service: CourseService

    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var showsRun = false
    @State private var showsDeleteConfirm = false
    @State private var deleteFailed: String?

    private var isMine: Bool { auth.userID == course.ownerID }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CourseMapView(path: course.path)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 8) {
                    Text(course.name).font(.title3.weight(.semibold))
                    HStack(spacing: 6) {
                        Text(String(format: "%.2f km", course.distanceKm))
                            .font(.headline).monospacedDigit()
                        Text("·").foregroundStyle(.tertiary)
                        Text(course.region).foregroundStyle(.secondary)
                        if !course.ownerNickname.isEmpty {
                            Text("·").foregroundStyle(.tertiary)
                            Text("\(course.ownerNickname) 등록").foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }

                Button {
                    showsRun = true
                } label: {
                    Label("이 코스로 달리기", systemImage: "figure.run")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.primary)
                .foregroundStyle(Color(.systemBackground))

                Text("코스는 올린 사람의 기록에서 앞뒤 150m를 잘라 만든 것이라, 실제 출발·도착 지점과는 조금 다릅니다.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if isMine {
                    Button("이 코스 삭제", role: .destructive) { showsDeleteConfirm = true }
                        .font(.subheadline)
                }
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
        .navigationTitle("코스")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showsRun) {
            RunView(startImmediately: true, course: course)
        }
        .confirmationDialog("이 코스를 삭제할까요?", isPresented: $showsDeleteConfirm, titleVisibility: .visible) {
            Button("삭제", role: .destructive) {
                Task {
                    do { try await service.delete(course); dismiss() }
                    catch { deleteFailed = "삭제하지 못했어요. 잠시 후 다시 시도해 주세요." }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("다른 사람 목록에서도 사라집니다.")
        }
        .alert("삭제 실패", isPresented: .constant(deleteFailed != nil)) {
            Button("확인") { deleteFailed = nil }
        } message: {
            Text(deleteFailed ?? "")
        }
    }
}
