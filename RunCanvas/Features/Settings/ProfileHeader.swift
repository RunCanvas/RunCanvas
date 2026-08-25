//
//  ProfileHeader.swift
//  RunCanvas
//
//  Created by 이다은 on 8/25/26.
//

import SwiftUI

struct ProfileHeader: View {
    @AppStorage("userNickname") private var userNickname: String = "다은"
    
    var body: some View {
        HStack(spacing: 8) {
            
            NavigationLink {
                ProfileView()
            } label: {
                HStack(spacing: 8) {
                    
                    // 프로필 이미지
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "person.fill")
                            .foregroundStyle(.secondary)
                    }
                    
                    // 닉네임
                    Text(userNickname)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }
            
            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        ProfileHeader()
            .padding(.horizontal, 24)
    }
}
