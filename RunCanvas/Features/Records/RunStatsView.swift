//
//  RunStatsView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/25/26.
//

import SwiftUI

struct RunStatsView: View {
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // MARK: - 전체 러닝 기록
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("전체 기록")
                            .font(.headline)
                        
                        HStack(spacing: 12) {
                            StatCard(
                                title: "총 거리",
                                value: "23.4",
                                unit: "km"
                            )
                            
                            StatCard(
                                title: "러닝 횟수",
                                value: "5",
                                unit: "회"
                            )
                        }
                        
                        HStack(spacing: 12) {
                            StatCard(
                                title: "평균 페이스",
                                value: "6'12\"",
                                unit: "/km"
                            )
                            
                            StatCard(
                                title: "최장 거리",
                                value: "7.2",
                                unit: "km"
                            )
                        }
                    }
                    
                    // MARK: - 이번 주
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("이번 주")
                            .font(.headline)
                        
                        VStack(spacing: 18) {
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("주간 목표")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    
                                    Text("20 km")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 6) {
                                    Text("달성 거리")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    
                                    Text("8.6 km")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                }
                            }
                            
                            // 진행률
                            VStack(spacing: 8) {
                                ProgressView(value: 8.6, total: 20)
                                    .tint(.black)
                                
                                HStack {
                                    Text("43% 달성")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    Spacer()
                                    
                                    Text("11.4 km 남음")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(20)
                        .background(Color.gray.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    
                    // MARK: - 최근 기록
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("최근 러닝")
                            .font(.headline)
                        
                        RunStatHistoryRow(
                            date: "8월 24일",
                            distance: "5.24 km",
                            time: "32:18",
                            pace: "6'10\""
                        )
                        
                        RunStatHistoryRow(
                            date: "8월 22일",
                            distance: "3.10 km",
                            time: "19:42",
                            pace: "6'22\""
                        )
                        
                        RunStatHistoryRow(
                            date: "8월 20일",
                            distance: "7.20 km",
                            time: "43:55",
                            pace: "6'06\""
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle("러닝 통계")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 통계 카드

struct StatCard: View {
    let title: String
    let value: String
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - 최근 러닝 기록

struct RunStatHistoryRow: View {
    let date: String
    let distance: String
    let time: String
    let pace: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Text(distance)
                    .font(.headline)
                    .fontWeight(.semibold)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 6) {
                Text(time)
                    .font(.subheadline)
                
                Text("\(pace) /km")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
        }
        .padding(16)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

#Preview {
    RunStatsView()
}
