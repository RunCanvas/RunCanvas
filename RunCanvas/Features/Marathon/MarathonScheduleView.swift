import SwiftUI

/// 마라톤·러닝 이벤트 일정. 카테고리(종류·거리)로 걸러 보고, 신청 페이지로 넘어간다.
struct MarathonScheduleView: View {
    @State private var service = MarathonService()
    @State private var category: MarathonCategory = .all
    @State private var course: MarathonCourse = .any

    private var sections: [MarathonSchedule.MonthSection] {
        MarathonSchedule(events: service.events).sections(category: category, course: course)
    }

    var body: some View {
        List {
            Section {
                filters
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            if let notice = service.fallbackNotice {
                Section {
                    Label(notice, systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.card)
            }

            if sections.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label(service.isLoading ? "불러오는 중" : "해당하는 일정이 없어요", systemImage: "calendar")
                    } description: {
                        Text(service.isLoading ? "잠시만 기다려 주세요." : "카테고리를 바꿔 보세요.")
                    }
                }
                .listRowBackground(Color.clear)
            }

            ForEach(sections) { section in
                Section(header: Text(header(for: section))) {
                    ForEach(section.events) { event in
                        MarathonRow(event: event)
                    }
                }
                .listRowBackground(Color.card)
            }

            Section {
                Text("출처: 공공데이터포털(문화체육관광부) · kormarathon.com\n일정은 주최 측 사정으로 바뀔 수 있어요. 신청 전 공식 공지를 확인해 주세요.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .appListTone()
        .navigationTitle("마라톤 일정")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await service.load() }
        .task { await service.load() }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            chipRow(MarathonCategory.allCases, selected: category) { category = $0 }
            chipRow(MarathonCourse.allCases, selected: course) { course = $0 }
        }
    }

    private func chipRow<T: Identifiable & RawRepresentable & Equatable>(
        _ items: [T], selected: T, onSelect: @escaping (T) -> Void
    ) -> some View where T.RawValue == String {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    let isOn = item == selected
                    Button { onSelect(item) } label: {
                        Text(item.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(isOn ? Color.primary : Color.card, in: Capsule())
                            .foregroundStyle(isOn ? Color(.systemBackground) : .primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// 앱이 한국어 전용이라 기기 로케일에 맡기지 않는다 ("September 2026" 대신 "2026년 9월")
    private func header(for section: MarathonSchedule.MonthSection) -> String {
        guard let start = section.monthStart else { return "날짜 미정" }
        let parts = Calendar.current.dateComponents([.year, .month], from: start)
        return "\(parts.year ?? 0)년 \(parts.month ?? 0)월"
    }
}

private struct MarathonRow: View {
    let event: MarathonEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(dateText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(event.name)
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if event.isAcceptingSignups {
                    Text("접수 중")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary, in: Capsule())
                        .foregroundStyle(Color(.systemBackground))
                }
            }

            Text([event.region, event.place.isEmpty ? nil : event.place].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)

            if !event.courses.isEmpty {
                Text(event.courses.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let deadline = event.registrationEnd, event.isAcceptingSignups {
                Text("신청 마감 \(Calendar.current.component(.month, from: deadline))월 \(Calendar.current.component(.day, from: deadline))일")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let url = event.signupURL {
                Link("신청 페이지", destination: url)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var dateText: String {
        guard let date = event.date else { return "미정" }
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        return String(format: "%02d.%02d", parts.month ?? 0, parts.day ?? 0)
    }
}

#Preview {
    NavigationStack { MarathonScheduleView() }
}
