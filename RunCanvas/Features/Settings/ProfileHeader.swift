import SwiftUI

/// 홈 상단. 예전엔 아바타와 닉네임만 있어 오른쪽이 통째로 비어 있었다 —
/// 러너가 홈에서 한눈에 알고 싶은 것(내가 누구인지 · 어디까지 왔는지 · 이번 주 얼마나 남았는지)을 담는다.
/// 색도 상자도 쓰지 않는다: 레벨 컬러는 주요 버튼에만 쓴다는 규칙 그대로이고,
/// 카드로 감싸면 지도·버튼·기록 행까지 상자가 네 겹이 돼 화면이 무거워진다(나이키·스트라바가 헤더에 상자를 안 쓰는 이유).
struct ProfileHeader: View {
    /// 레벨 계산용 누적 거리 · 이번 주 거리. 홈이 이미 들고 있는 값이라 여기서 다시 조회하지 않는다.
    var totalMeters: Double = 0
    var weekMeters: Double = 0

    @AppStorage("userNickname") private var userNickname: String = ""
    @AppStorage("avatarURL") private var avatarURL: String = ""
    @AppStorage("weeklyTargetDistance") private var weeklyTargetKm: Double = 20

    private var level: Level { .forTotalDistance(totalMeters) }
    private var weekKm: Double { weekMeters / 1000 }
    private var targetKm: Double { weeklyTargetKm > 0 ? weeklyTargetKm : 20 }
    private var weekProgress: Double { min(weekKm / targetKm, 1) }

    /// 시간대 인사. 날짜·요일과 달리 기기 로케일에 맡길 게 없어 한국어로 고정한다.
    private var greeting: String {
        switch Calendar.appGregorian.component(.hour, from: .now) {
        case 5..<11: "좋은 아침이에요"
        case 11..<18: "오늘도 달려볼까요"
        default: "좋은 저녁이에요"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink {
                ProfileEditView()
            } label: {
                HStack(spacing: 12) {
                    AvatarView(urlString: avatarURL, size: 44)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(greeting)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("\(userNickname.isEmpty ? "러너" : userNickname) 님")
                            .font(.title3.bold())
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)   // 레벨 틴트가 닉네임 색을 바꾸지 않게
            .accessibilityLabel("프로필 편집, \(userNickname.isEmpty ? "러너" : userNickname), \(level.title) 레벨")

            VStack(spacing: 7) {
                HStack {
                    Text("이번 주 · \(level.title) 레벨")
                    Spacer()
                    Text("\(RunMath.formatKm(weekMeters)) / \(targetKm.formatted(.number.precision(.fractionLength(0...1)))) km")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                progressBar
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("이번 주 \(RunMath.formatKm(weekMeters))킬로미터, 목표 \(Int(targetKm))킬로미터")
        }
    }

    /// 왜 직접 그리는가: 기본 ProgressView 는 트랙이 배경에 묻히고 두께도 못 줄인다.
    /// 색은 안 쓰고 불투명도만으로 대비를 낸다.
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule()
                    .fill(Color.primary)
                    // 0 이 아닌데 선이 안 보이면 "기록이 없다"로 오해한다 — 최소 폭을 준다
                    .frame(width: weekProgress > 0
                           ? max(geometry.size.width * weekProgress, 4)
                           : 0)
            }
        }
        .frame(height: 4)
    }
}

#Preview {
    NavigationStack {
        ProfileHeader(totalMeters: 253_000, weekMeters: 12_400)
            .padding(20)
    }
    .environment(AuthService())
}
