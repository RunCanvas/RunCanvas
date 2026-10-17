//
//  RunResultView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/24/26.
//

import SwiftUI
import SwiftData

/// 러닝 종료 직후: 상세(런꾸하기 포함) + 새로 딴 뱃지 토스트 + 홈 버튼
struct RunResultView: View {
    let run: Run

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Query private var ownerRuns: [Run]
    @State private var newBadges: [Badge] = []
    @State private var completedChallenges: [Challenge] = []
    @State private var didRecordAchievements = false

    init(run: Run) {
        self.run = run
        let owner = run.ownerID
        _ownerRuns = Query(filter: #Predicate<Run> { $0.ownerID == owner })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("러닝 완료").font(.largeTitle.bold()).padding(.top, 20)
                RunDetailView(run: run)

                if !completedChallenges.isEmpty {
                    Label("챌린지 완료: \(completedChallenges.map(\.title).joined(separator: ", "))", systemImage: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }

                // 꾸미기는 위 상세 화면의 '런꾸하기' 하나로 — 같은 편집기를 여는 주요 버튼이 두 개였다
                Button { dismiss() } label: {
                    Text("홈으로")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .badgeEarnedToast($newBadges)
        .onAppear {
            // 상세 화면의 런꾸 편집기(fullScreenCover)를 닫으면 onAppear 가 또 온다. 두 번째 기록은 이미 저장돼 [] 를 돌려줘
            // '챌린지 완료' 줄과 떠 있던 뱃지 토스트가 지워졌다 — 한 번만 기록한다
            guard !didRecordAchievements else { return }
            didRecordAchievements = true
            let badgeRuns = ownerRuns.map(\.badgeRun)
            newBadges = BadgeStore.recordNewlyEarned(from: badgeRuns, ownerID: run.ownerID)
            completedChallenges = BadgeStore.recordCompletedChallenges(from: badgeRuns, ownerID: run.ownerID)
        }
        .task {
            guard auth.canSync else { return }
            await SyncService.sync(context: context, ownerID: run.ownerID)   // 이번 기록 + 새 뱃지 서버 사본
        }
    }
}
