import SwiftUI
import MapKit

/// 코스를 지도에서 고르는 화면.
///
/// 경로를 전부 그리면 도시 하나가 실타래가 된다 — 그래서 평소엔 **출발점만** 찍고,
/// 고른 코스 하나만 선을 그린다. 어디서 출발하는 코스가 있는지가 지도에서 알고 싶은 것이다.
struct CourseMapBrowseView: View {
    let courses: [Course]
    let service: CourseService
    let onRetry: () async -> Void

    @State private var selected: Course?
    @State private var position: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $position, selection: .constant(nil)) {
                if let selected, selected.path.count > 1 {
                    MapPolyline(coordinates: selected.coordinates)
                        .stroke(.white, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: selected.coordinates)
                        .stroke(Color.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }

                ForEach(courses) { course in
                    if let start = course.coordinates.first {
                        Annotation(course.name, coordinate: start) {
                            pin(for: course)
                        }
                        .annotationTitles(.hidden)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControlVisibility(.hidden)
            .onChange(of: courses.map(\.id)) { _, ids in
                guard let selected, !ids.contains(selected.id) else { return }
                // 삭제·필터 변경으로 목록에서 빠진 값 복사본을 상세 카드에 남겨 두지 않는다.
                withAnimation {
                    self.selected = nil
                    position = .automatic
                }
            }

            if service.isLoading, courses.isEmpty {
                Label("코스를 불러오는 중…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
            } else if let notice = service.failureNotice {
                VStack(alignment: .leading, spacing: 10) {
                    Label(notice, systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("다시 시도") { Task { await onRetry() } }
                        .font(.footnote.weight(.semibold))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            } else if courses.isEmpty {
                Text("이 지역에는 아직 코스가 없어요")
                    .font(.subheadline)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
            } else if let selected {
                selectedCard(selected)
            } else {
                Text("핀을 눌러 코스를 골라 보세요 · \(service.totalCount)개")
                    .font(.footnote)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 24)
            }
        }
    }

    /// 고른 코스는 크게, 나머지는 점으로 — 핀이 수십 개여도 지도가 읽힌다
    private func pin(for course: Course) -> some View {
        let isSelected = selected?.id == course.id
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                selected = isSelected ? nil : course
                if !isSelected { position = .region(region(of: course)) }
            }
        } label: {
            Image(systemName: "figure.run")
                .font(.system(size: isSelected ? 15 : 11, weight: .bold))
                .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
                .padding(isSelected ? 9 : 6)
                .background(isSelected ? Color.primary : Color(.systemBackground), in: Circle())
                .overlay(Circle().stroke(Color.primary.opacity(isSelected ? 0 : 0.35), lineWidth: 1.5))
                .shadow(radius: isSelected ? 4 : 1)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(course.name), \(String(format: "%.1f", course.distanceKm))km")
    }

    private func selectedCard(_ course: Course) -> some View {
        NavigationLink {
            CourseDetailView(course: course, service: service)
        } label: {
            HStack(spacing: 12) {
                CoursePathThumbnail(path: course.path)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(course.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("\(String(format: "%.2f km", course.distanceKm)) · \(course.region)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if !course.ownerNickname.isEmpty {
                        Text("\(course.ownerNickname) 등록").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// 코스가 화면에 꽉 차게 — 여유 40%
    private func region(of course: Course) -> MKCoordinateRegion {
        let lats = course.path.map(\.lat), lons = course.path.map(\.lon)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 37.5665, longitude: 126.9780),
                                      span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.4, 0.005),
                                   longitudeDelta: max((maxLon - minLon) * 1.4, 0.005))
        )
    }
}
