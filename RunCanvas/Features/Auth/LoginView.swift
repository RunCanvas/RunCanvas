//
//  LoginView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/24/26.
//

import SwiftUI

struct LoginView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                
                Spacer()
                
                VStack(spacing: 8) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 45))
                    
                    Text("RunCanvas")
                        .font(.system(size: 30, weight: .bold))
                }
                
                Spacer()
                
                VStack(spacing: 16) {
                    TextField("이메일", text: .constant(""))
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    
                    SecureField("비밀번호", text: .constant(""))
                        .textFieldStyle(.roundedBorder)
                }
                
                NavigationLink {
                    RootTabView()
                } label: {
                    Text("로그인")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                NavigationLink {
                    SignUpView()
                } label: {
                    Text("회원가입하기")
                        .font(.subheadline)
                        .foregroundStyle(.gray)
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}

#Preview {
    LoginView()
}
