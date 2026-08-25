//
//  RunResultView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/24/26.
//

import SwiftUI

struct RunResultView: View {
    let elapsedTime: Int
    let totalDistance: Double
    
    // 저장된 체중
    @AppStorage("userWeight") private var userWeight: Double = 60.0
    
    private var formattedTime: String {
        let minutes = elapsedTime / 60
        let seconds = elapsedTime % 60
        
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    private var formattedDistance: String {
        String(format: "%.2f", totalDistance / 1000)
    }
    
    // 페이스 표시
    private var formattedPace: String {
        let distanceInKm = totalDistance / 1000
        
        guard distanceInKm > 0 else {
            return "--'--\""
        }
        
        let paceInSeconds = Double(elapsedTime) / distanceInKm
        
        let minutes = Int(paceInSeconds) / 60
        let seconds = Int(paceInSeconds) % 60
        
        return String(format: "%02d'%02d\"", minutes, seconds)
    }
    
    // 칼로리 계산
    private var calories: Int {
        let distanceInKm = totalDistance / 1000
        
        let calculatedCalories = userWeight * distanceInKm * 1.036
        
        return Int(calculatedCalories.rounded())
    }
    
    var body: some View {
        VStack(spacing: 0) {
            
            // 상단
            Text("러닝 완료 🎉")
                .font(.system(size: 30, weight: .bold))
                .padding(.top, 40)
            
            Spacer()
            
            // 거리
            VStack(spacing: 8) {
                Text("거리")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text(formattedDistance)
                    .font(.system(size: 64, weight: .bold))
                
                Text("km")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // 러닝 기록
            HStack(spacing: 0) {
                ResultStatView(
                    title: "시간",
                    value: formattedTime
                )
                
                Divider()
                    .frame(height: 50)
                
                ResultStatView(
                    title: "페이스",
                    value: formattedPace
                )
                
                Divider()
                    .frame(height: 50)
                
                ResultStatView(
                    title: "칼로리",
                    value: "\(calories) kcal"
                )
            }
            .padding(.horizontal, 20)
            
            Spacer()
            
            // 사진 꾸미기 버튼
            Button {
                // 나중에 사진 꾸미기 화면 연결
            } label: {
                HStack {
                    Image(systemName: "photo")
                    Text("사진으로 꾸미기")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            
            // 홈으로
            Button {
                // 나중에 홈으로 이동
            } label: {
                Text("홈으로")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 16)
            }
            
            Spacer()
                .frame(height: 30)
        }
    }
}

struct ResultStatView: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    RunResultView(
        elapsedTime: 1920,
        totalDistance: 5240
    )
}
