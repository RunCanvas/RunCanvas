import SwiftUI

/// 설정·프로필 화면 공용: 제목 + 회색 카드
struct ProfileSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            VStack {
                content
            }
            .padding(.horizontal, 16)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

/// 라벨 · 오른쪽 정렬 입력 · 단위
struct ProfileTextFieldRow: View {
    let title: String
    @Binding var text: String
    var unit: String = ""
    var keyboardType: UIKeyboardType

    var body: some View {
        HStack {
            Text(title)

            Spacer()

            TextField("", text: $text)
                .keyboardType(keyboardType)
                .multilineTextAlignment(.trailing)
                .frame(width: 120)

            if !unit.isEmpty {
                Text(unit)
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .leading)
            }
        }
        .padding(.vertical, 14)
    }
}

/// 라벨 · 오른쪽 내용 · chevron — 탭하면 다른 화면으로
struct ProfileLinkRow<Trailing: View>: View {
    let title: String
    var titleColor: Color = .primary
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(titleColor)
            Spacer()
            trailing()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 14)
    }
}

/// 원형 아바타 (URL 없으면 사람 아이콘)
struct AvatarView: View {
    let urlString: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.15))
                .frame(width: size, height: size)

            if let url = URL(string: urlString), !urlString.isEmpty {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView()
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
