//
//  SplashView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/24/26.
//

import SwiftUI

/// 세션·프로필 확인 동안 보여주는 정적 화면. 다음 화면 분기는 AppRouter가 한다.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "figure.run")
                    .font(.system(size: 60))
                    .foregroundStyle(.primary)

                Text("RunCanvas")
                    .font(.largeTitle.bold())

                Text("Every Run, A Canvas.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    SplashView()
}
