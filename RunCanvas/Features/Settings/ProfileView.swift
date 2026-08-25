//
//  ProfileView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/24/26.
//

import SwiftUI

struct ProfileView: View {
    // 저장되는 사용자 정보
    @AppStorage("userNickname") private var userNickname: String = "다은"
    @AppStorage("userWeight") private var userWeight: Double = 60.0
    @AppStorage("userHeight") private var userHeight: Double = 165.0
    
    // 러닝 설정
    @AppStorage("targetDistance") private var targetDistance: Double = 5.0
    @AppStorage("weeklyTargetDistance") private var weeklyTargetDistance: Double = 20.0
    
    // 앱 설정
    @AppStorage("isNotificationEnabled") private var isNotificationEnabled: Bool = true
    @AppStorage("distanceUnit") private var distanceUnit: String = "km"
    
    @State private var nicknameText = ""
    @State private var weightText = ""
    @State private var heightText = ""
    @State private var targetDistanceText = ""
    @State private var weeklyTargetDistanceText = ""
    
    @State private var isSaved = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // 프로필 정보
                    profileSection
                    
                    // 러닝 설정
                    runningSettingSection
                    
                    // 앱 설정
                    appSettingSection
                    
                    // 계정
                    accountSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .navigationTitle("프로필")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                loadSavedData()
            }
        }
    }
    
    // MARK: - 프로필 정보
    
    private var profileSection: some View {
        ProfileSection(title: "기본 정보") {
            VStack(spacing: 0) {
                
                ProfileTextFieldRow(
                    title: "닉네임",
                    text: $nicknameText,
                    keyboardType: .default
                )
                
                Divider()
                
                ProfileTextFieldRow(
                    title: "체중",
                    text: $weightText,
                    unit: "kg",
                    keyboardType: .decimalPad
                )
                
                Divider()
                
                ProfileTextFieldRow(
                    title: "키",
                    text: $heightText,
                    unit: "cm",
                    keyboardType: .decimalPad
                )
            }
        }
    }
    
    // MARK: - 러닝 설정
    
    private var runningSettingSection: some View {
        ProfileSection(title: "러닝 설정") {
            VStack(spacing: 0) {
                
                ProfileTextFieldRow(
                    title: "1회 목표 거리",
                    text: $targetDistanceText,
                    unit: "km",
                    keyboardType: .decimalPad
                )
                
                Divider()
                
                ProfileTextFieldRow(
                    title: "주간 목표 거리",
                    text: $weeklyTargetDistanceText,
                    unit: "km",
                    keyboardType: .decimalPad
                )
            }
        }
    }
    
    // MARK: - 앱 설정
    
    private var appSettingSection: some View {
        ProfileSection(title: "앱 설정") {
            VStack(spacing: 0) {
                
                HStack {
                    Text("알림")
                    
                    Spacer()
                    
                    Toggle("", isOn: $isNotificationEnabled)
                        .labelsHidden()
                }
                .padding(.vertical, 14)
                
                Divider()
                
                HStack {
                    Text("거리 단위")
                    
                    Spacer()
                    
                    Picker("", selection: $distanceUnit) {
                        Text("km").tag("km")
                        Text("mile").tag("mile")
                    }
                    .pickerStyle(.menu)
                }
                .padding(.vertical, 14)
            }
        }
    }
    
    // MARK: - 계정
    
    private var accountSection: some View {
        VStack(spacing: 12) {
            
            Button {
                saveData()
            } label: {
                Text("저장")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            
            if isSaved {
                Text("저장되었습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Button {
                // 나중에 로그아웃 기능 연결
            } label: {
                Text("로그아웃")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - 데이터
    
    private func loadSavedData() {
        nicknameText = userNickname
        weightText = String(format: "%.1f", userWeight)
        heightText = String(format: "%.1f", userHeight)
        targetDistanceText = String(format: "%.1f", targetDistance)
        weeklyTargetDistanceText = String(format: "%.1f", weeklyTargetDistance)
    }
    
    private func saveData() {
        if !nicknameText.isEmpty {
            userNickname = nicknameText
        }
        
        if let weight = Double(weightText), weight > 0 {
            userWeight = weight
        }
        
        if let height = Double(heightText), height > 0 {
            userHeight = height
        }
        
        if let target = Double(targetDistanceText), target > 0 {
            targetDistance = target
        }
        
        if let weeklyTarget = Double(weeklyTargetDistanceText), weeklyTarget > 0 {
            weeklyTargetDistance = weeklyTarget
        }
        
        isSaved = true
    }
}

// MARK: - 프로필 섹션

struct ProfileSection<Content: View>: View {
    let title: String
    let content: Content
    
    init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
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

// MARK: - 입력 행

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

#Preview {
    ProfileView()
}
