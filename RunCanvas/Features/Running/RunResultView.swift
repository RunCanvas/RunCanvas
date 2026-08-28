//
//  RunResultView.swift
//  RunCanvas
//
//  Created by 이다은 on 8/24/26.
//

import SwiftUI
import SwiftData

/// 러닝 종료 직후: 상세 + 새로 딴 뱃지 토스트 + 런꾸/홈 버튼
struct RunResultView: View {
    let run: Run

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AuthService.self) private var auth
    @Query private var ownerRuns: [Run]
    @State private var newBadges: [Badge] = []
    @State private var completedChallenges: [Challenge] = []

    init(run: Run) {
        self.run = run
        let owner = run.ownerID
        _ownerRuns = Query(filter: #Predicate<Run> { $0.ownerID == owner })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("러닝 완료").font(.system(size: 30, weight: .bold)).padding(.top, 24)
                RunDetailView(run: run)

                if !completedChallenges.isEmpty {
                    Label("챌린지 완료: \(completedChallenges.map(\.title).joined(separator: ", "))", systemImage: "checkmark.seal.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }

                PrimaryButton(title: "사진으로 꾸미기", systemImage: "photo") {
                    // Phase 6: CanvasFlowView(run: run) 연결
                }
                .padding(.horizontal, 24)

                Button("홈으로") { dismiss() }
                    .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 16)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .badgeEarnedToast($newBadges)
        .onAppear {
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
