import SwiftUI

/// 기록 상세: 지도 경로 + 수치. 홈·기록 목록에서 push, 결과 화면에서도 재사용.
struct RunDetailView: View {
    let run: Run

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                RouteMapView(route: run.route)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                if let decoratedImage = CanvasStorage.image(filename: run.decoratedImageFilename) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("나의 런꾸")
                            .font(.headline)
                        Image(uiImage: decoratedImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }

                VStack(spacing: 8) {
                    Text(RunMath.formatKm(run.distanceMeters)).font(.system(size: 56, weight: .bold))
                    Text("km").foregroundStyle(.secondary)
                }

                HStack(spacing: 0) {
                    StatLabel(title: "시간", value: RunMath.formatDuration(run.movingSeconds))
                    StatLabel(title: "페이스", value: RunMath.formatPace(run.paceSecondsPerKm))
                    StatLabel(title: "칼로리", value: "\(Int(run.calories.rounded()))")
                    StatLabel(title: "평균 BPM", value: run.averageHeartRate.map { "\(Int($0))" } ?? "--")
                }

                Text(run.startedAt.formatted(date: .long, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .navigationTitle("러닝 상세")
        .navigationBarTitleDisplayMode(.inline)
    }
}
