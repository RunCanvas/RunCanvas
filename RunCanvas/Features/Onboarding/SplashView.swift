//
//  SplashView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/24/26.
//

import SwiftUI

struct SplashView: View {
    @State private var showLogin = false

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Image(systemName: "figure.run")
                    .font(.system(size: 60))
                    .foregroundStyle(.black)

                Text("RunCanvas")
                    .font(.system(size: 32, weight: .bold))

                Text("Every Run, A Canvas.")
                    .font(.system(size: 15))
                    .foregroundStyle(.gray)
            }
        }
        .fullScreenCover(isPresented: $showLogin) {
            LoginView()
        }
        .task {
            try? await Task.sleep(for: .seconds(2))
            showLogin = true
        }
    }
}

#Preview {
    SplashView()
}

