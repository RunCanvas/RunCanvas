import SwiftUI

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
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    case .failure: placeholderIcon          // 로드 실패 시 스피너가 계속 돌지 않게
                    default: ProgressView()
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                placeholderIcon
            }
        }
    }

    private var placeholderIcon: some View {
        Image(systemName: "person.fill")
            .font(.system(size: size * 0.4))
            .foregroundStyle(.secondary)
    }
}
