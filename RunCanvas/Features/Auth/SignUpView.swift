//
//  SignUpView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/24/26.
//

import SwiftUI

struct SignUpView: View {
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirm = ""

    var body: some View {
        VStack(spacing: 24) {
            
            Text("회원가입")
                .font(.system(size: 30, weight: .bold))
                .padding(.bottom, 20)
            
            VStack(spacing: 16) {
                TextField("이름", text: $name)
                    .textFieldStyle(.roundedBorder)
                
                TextField("이메일", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                
                SecureField("비밀번호", text: $password)
                    .textFieldStyle(.roundedBorder)
                
                SecureField("비밀번호 확인", text: $passwordConfirm)
                    .textFieldStyle(.roundedBorder)
            }
            
            Button {
                // 나중에 실제 회원가입 기능 추가
            } label: {
                Text("회원가입")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
    }
}

#Preview {
    SignUpView()
}
