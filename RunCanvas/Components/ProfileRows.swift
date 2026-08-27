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
