//
//  ProfileHeader.swift
//  RunCanvas
//
//  Created by 이다은 on 8/25/26.
//

import SwiftUI

struct ProfileHeader: View {
    @AppStorage("userNickname") private var userNickname: String = ""
    @AppStorage("avatarURL") private var avatarURL: String = ""
    
    var body: some View {
        HStack(spacing: 8) {
            
            NavigationLink {
                ProfileEditView()
            } label: {
                HStack(spacing: 8) {
                    
                    // 프로필 이미지
                    AvatarView(urlString: avatarURL, size: 36)
                    
                    // 닉네임
                    Text(userNickname.isEmpty ? "러너" : userNickname)   // 설정 화면과 같은 기본값
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)   // 레벨 틴트가 닉네임 색을 바꾸지 않게
            
            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        ProfileHeader()
            .padding(.horizontal, 20)
    }
    .environment(AuthService())
}
