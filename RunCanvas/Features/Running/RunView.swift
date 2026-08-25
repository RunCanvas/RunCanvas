//
//  RunView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/24/26.
//

import SwiftUI

struct RunView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var isRunning = false
    @State private var elapsedTime = 0
    @State private var timer: Timer?
    @State private var isShowingResult = false
    
    // 화면에 들어오자마자 러닝을 시작할지 여부
    let startImmediately: Bool
    
    // 저장된 체중
    @AppStorage("userWeight") private var userWeight: Double = 60.0
    
    var body: some View {
        VStack(spacing: 0) {
            
            // 상단
            HStack {
                Text("러닝")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            Spacer()
            
            // 거리
            VStack(spacing: 8) {
                Text("거리")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Text(String(format: "%.2f", locationManager.totalDistance / 1000))
                    .font(.system(size: 64, weight: .bold))
                
                Text("km")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // 러닝 정보
            HStack(spacing: 0) {
                RunStatView(
                    title: "시간",
                    value: formattedTime
                )
                
                Divider()
                    .frame(height: 50)
                
                RunStatView(
                    title: "페이스",
                    value: formattedPace
                )
                
                Divider()
                    .frame(height: 50)
                
                RunStatView(
                    title: "칼로리",
                    value: "\(calories) kcal"
                )
            }
            
            Spacer()
            
            // 러닝 시작 / 일시정지 버튼
            Button {
                if isRunning {
                    pauseRun()
                } else {
                    startRun()
                }
            } label: {
                HStack {
                    Image(systemName: isRunning ? "pause.fill" : "figure.run")
                    
                    Text(isRunning ? "일시정지" : "러닝 시작")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            
            // 러닝 종료 버튼
            if isRunning {
                Button {
                    finishRun()
                } label: {
                    Text("러닝 종료")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .padding(.top, 16)
                }
            }
            
            Spacer()
                .frame(height: 30)
        }
        .onAppear {
            if startImmediately {
                startRun()
            }
        }
        .fullScreenCover(isPresented: $isShowingResult) {
            RunResultView(
                elapsedTime: elapsedTime,
                totalDistance: locationManager.totalDistance
            )
        }
    }

    // 시간 표시
    private var formattedTime: String {
        let minutes = elapsedTime / 60
        let seconds = elapsedTime % 60
        
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // 페이스 표시
    private var formattedPace: String {
        let distanceInKm = locationManager.totalDistance / 1000
        
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
        let distanceInKm = locationManager.totalDistance / 1000
        
        let calculatedCalories = userWeight * distanceInKm * 1.036
        
        return Int(calculatedCalories.rounded())
    }

    // 러닝 시작
    private func startRun() {
        print("🔥 startRun 실행됨")
        
        isRunning = true
        
        locationManager.requestPermission()
        locationManager.startUpdatingLocation()
        
        timer?.invalidate()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedTime += 1
        }
    }

    // 러닝 일시정지
    private func pauseRun() {
        isRunning = false
        
        timer?.invalidate()
        timer = nil
        
        locationManager.stopUpdatingLocation()
    }

    // 러닝 종료
    private func finishRun() {
        timer?.invalidate()
        timer = nil
        
        locationManager.stopUpdatingLocation()
        
        isRunning = false
        isShowingResult = true
    }
}

// 러닝 기록 한 칸
struct RunStatView: View {
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
    RunView(startImmediately: true)
}
