//
//  HomeView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/24/26.
//

import SwiftUI

struct RunnerHomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                
                // 상단 프로필
                ProfileHeader()
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                
                ScrollView {
                    VStack(spacing: 28) {
                        
                        // 오늘의 러닝
                        VStack(spacing: 12) {
                            Text("오늘의 러닝")
                                .font(.headline)
                            
                            Text("0.00")
                                .font(.system(size: 52, weight: .bold))
                            
                            Text("km")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 40)
                        
                        // 러닝 시작 버튼
                        NavigationLink {
                            RunView(startImmediately: true)
                        } label: {
                            HStack {
                                Image(systemName: "figure.run")
                                Text("러닝 시작")
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        
                        // 최근 러닝
                        VStack(alignment: .leading, spacing: 16) {
                            Text("최근 러닝")
                                .font(.headline)
                            
                            RunHistoryRow(
                                distance: "5.24 km",
                                time: "32:18"
                            )
                            
                            RunHistoryRow(
                                distance: "3.10 km",
                                time: "19:42"
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                }
                
                // 하단 탭
                HStack {
                    
                    // 홈
                    TabButton(
                        icon: "house.fill",
                        title: "홈"
                    )
                    
                    Spacer()
                    
                    // 러닝
                    NavigationLink {
                        RunView(startImmediately: false)
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "figure.run")
                            Text("러닝")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.black)
                    
                    Spacer()
                    
                    // 나의 기록
                    NavigationLink {
                        RunStatsView()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "chart.bar.fill")
                            Text("나의 기록")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.black)
                    
                    Spacer()
                    
                    // 런꾸
                    NavigationLink {
                        RunDecorateView()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "photo")
                            Text("런꾸")
                                .font(.caption)
                        }
                    }
                    .foregroundStyle(.black)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
    }
}

// MARK: - 최근 러닝 한 줄

struct RunHistoryRow: View {
    let distance: String
    let time: String
    
    var body: some View {
        HStack {
            Image(systemName: "figure.run")
            
            VStack(alignment: .leading) {
                Text(distance)
                    .fontWeight(.semibold)
                
                Text(time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 하단 탭 버튼

struct TabButton: View {
    let icon: String
    let title: String
    
    var body: some View {
        Button {
            // 홈 버튼
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
                    .font(.caption)
            }
        }
        .foregroundStyle(.black)
    }
}

#Preview {
    RunnerHomeView()
        .environment(AuthService())
}
