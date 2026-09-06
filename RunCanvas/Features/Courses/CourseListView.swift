import SwiftUI

/// 공유 코스 목록. 지역으로 거르고, 카드를 누르면 상세 → 따라뛰기.
/// 톤은 마라톤 일정·뱃지 화면과 같다(회색 카드 · 16 라운드 · 20 여백).
struct CourseListView: View {
    @State private var service = CourseService()
    @State private var region = KoreaRegion.all

    var body: some View {
        VStack(spacing: 0) {
            ChipRow(titles: chips, selected: region) { picked in
                region = picked
                Task { await service.load(region: picked) }
            }
            .padding(.vertical, 10)
            Divider()
            list
        }
        .background(Color(.systemBackground))
        .navigationTitle("러닝 코스")
        .navigationBarTitleDisplayMode(.inline)
        .task { await service.load(region: region) }
    }

    /// 서버가 지역으로 이미 걸러 주므로, 칩은 앱이 아는 지역을 전부 보여준다 —
    /// 목록에 있는 것만 만들면 "그 지역엔 아직 코스가 없다"는 걸 알 방법이 없다.
    private var chips: [String] { [KoreaRegion.all] + KoreaRegion.order }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if let notice = service.failureNotice {
                    Label(notice, systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.card, in: RoundedRectangle(cornerRadius: 12))
                }

                if service.courses.isEmpty {
                    ContentUnavailableView {
                        Label(service.isLoading ? "불러오는 중" : "등록된 코스가 없어요", systemImage: "map")
                    } description: {
                        Text(service.isLoading ? "잠시만 기다려 주세요."
                             : "기록 상세에서 마음에 든 코스를 올려 보세요.")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }

                ForEach(service.courses) { course in
                    NavigationLink {
                        CourseDetailView(course: course, service: service)
                    } label: {
                        CourseCard(course: course)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
        }
        .refreshable { await service.load(region: region) }
    }
}

struct CourseCard: View {
    let course: Course

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CourseMapView(path: course.path, isInteractive: false)
                .frame(height: 130)
                .clipped()

            VStack(alignment: .leading, spacing: 6) {
                Text(course.name)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    Text(String(format: "%.2f km", course.distanceKm))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Text("·").foregroundStyle(.tertiary)
                    Text(course.region)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if !course.ownerNickname.isEmpty {
                        Text(course.ownerNickname)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(16)
        }
        .background(Color.card)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}
