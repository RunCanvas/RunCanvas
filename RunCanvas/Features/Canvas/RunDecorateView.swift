//
//  RunDecorateView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/25/26.
//

import SwiftUI

struct RunDecorateView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                
                // 상단 프로필
                ProfileHeader()
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                
                ScrollView {
                    VStack(spacing: 24) {
                        
                        // 제목
                        VStack(spacing: 8) {
                            Text("런꾸")
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Text("러닝 사진을 예쁘게 꾸며보세요")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 30)
                        
                        // 사진 선택 영역
                        Button {
                            // 나중에 사진 선택 기능 연결
                        } label: {
                            VStack(spacing: 16) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.secondary)
                                
                                Text("사진 선택")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                
                                Text("러닝 사진을 선택해주세요")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 320)
                            .background(Color.gray.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                        
                        // 꾸미기 기능
                        VStack(alignment: .leading, spacing: 16) {
                            Text("꾸미기")
                                .font(.headline)
                            
                            HStack(spacing: 12) {
                                DecorateButton(
                                    icon: "textformat",
                                    title: "기록 추가"
                                )
                                
                                DecorateButton(
                                    icon: "paintpalette",
                                    title: "스타일"
                                )
                                
                                DecorateButton(
                                    icon: "square.grid.2x2",
                                    title: "레이아웃"
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
                }
            }
            .navigationBarHidden(true)
        }
    }
}

// MARK: - 꾸미기 버튼

struct DecorateButton: View {
    let icon: String
    let title: String
    
    var body: some View {
        Button {
            // 나중에 기능 연결
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                
                Text(title)
                    .font(.caption)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.gray.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}

#Preview {
    NavigationStack {
        RunDecorateView()
    }
}
