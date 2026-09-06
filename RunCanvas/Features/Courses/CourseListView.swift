import SwiftUI

/// 공유 코스 — 목록 또는 지도로 보고, 지역·정렬·내 코스만으로 좁힌다.
/// 톤은 마라톤 일정·뱃지 화면과 같다(회색 카드 · 16 라운드 · 20 여백).
struct CourseListView: View {
    @Environment(AuthService.self) private var auth
    @State private var service = CourseService()
    @State private var region = KoreaRegion.all
    @State private var sort: CourseSort = .newest
    @State private var mineOnly = false
    @State private var showsMap = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                FilterMenuPill(title: "지역", options: chips, allOption: KoreaRegion.all,
                               counts: service.regionCounts, selection: $region)
                if mineOnly {
                    Text("내 코스만")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Color.card, in: Capsule())
                }
                Spacer()
                Text("\(service.courses.count)개")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            Divider()

            if showsMap {
                CourseMapBrowseView(courses: service.courses, service: service)
            } else {
                list
            }
        }
        .background(Color(.systemBackground))
        .navigationTitle("러닝 코스")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsMap.toggle()
                } label: {
                    Label(showsMap ? "목록으로" : "지도로", systemImage: showsMap ? "list.bullet" : "map")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("보기 설정", systemImage: "arrow.up.arrow.down") {
                    Picker("정렬", selection: $sort) {
                        ForEach(CourseSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("내 코스만", isOn: $mineOnly)
                }
            }
        }
        .onChange(of: region) { Task { await reload() } }
        .onChange(of: sort) { Task { await reload() } }
        .onChange(of: mineOnly) { Task { await reload() } }
        .task { await reload() }
    }

    /// 서버가 지역으로 걸러 주므로 칩은 앱이 아는 지역을 전부 만들고 개수를 붙인다 —
    /// 목록에 있는 것만 만들면 "그 지역엔 아직 코스가 없다"는 걸 알 방법이 없다.
    private var chips: [String] { [KoreaRegion.all] + KoreaRegion.order }

    private func reload() async {
        await service.load(region: region, sort: sort, mineOnly: mineOnly, ownerID: auth.userID)
        await service.loadRegionCounts(mineOnly: mineOnly, ownerID: auth.userID)
    }

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
                        Label(service.isLoading ? "불러오는 중" : emptyTitle, systemImage: "map")
                    } description: {
                        Text(service.isLoading ? "잠시만 기다려 주세요." : emptyDescription)
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
        .refreshable { await reload() }
    }

    private var emptyTitle: String { mineOnly ? "올린 코스가 없어요" : "등록된 코스가 없어요" }
    private var emptyDescription: String {
        mineOnly ? "기록 상세에서 ‘코스로 등록’을 눌러 보세요." : "기록 상세에서 마음에 든 코스를 올려 보세요."
    }
}

struct CourseCard: View {
    let course: Course

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CoursePathThumbnail(path: course.path)
                .frame(height: 130)

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
