# RunCanvas

iOS app (SwiftUI, Xcode 26, iOS 18.5+).

`RunCanvas.xcodeproj` 를 Xcode로 열면 됩니다.

## 브랜치 규칙 (git-flow)

| 브랜치 | 용도 | 어디서 → 어디로 |
|---|---|---|
| `main` | 출시된 버전만. 직접 커밋 금지 | `release/*`, `hotfix/*` 머지 |
| `develop` | 다음 버전 통합. 기본 브랜치 | `feature/*` PR 머지 |
| `feature/<이름>` | 기능 하나 | `develop`에서 분기 → `develop`으로 PR |
| `release/<버전>` | 출시 준비(버전 올리기, 버그 수정) | `develop`에서 분기 → `main`+`develop` 머지 |
| `hotfix/<이름>` | 출시 버전 긴급 수정 | `main`에서 분기 → `main`+`develop` 머지 |

- PR은 상대방 리뷰 1명 승인 후 머지.
- `feature/*`, `release/*`, `hotfix/*`는 필요할 때 만들고, 머지 후 삭제.

## 폴더 구조

```
RunCanvas/
├── App/          RunCanvasApp, AppRouter(스플래시→로그인/프로필설정/탭), RootTabView(홈·기록·런꾸·설정)
├── Models/       Run(SwiftData, ownerID로 계정별), RoutePoint, RunDTO(서버 사본), Profile, Badge, Level, Challenge
├── Services/     Supabase, AuthService, ProfileService, SyncService, LocationService, VoiceCoach,
│                 RunMath, BadgeEngine, BadgeStore, ChallengeEngine
├── Features/     화면 묶음별 폴더
│   ├── Onboarding/ SplashView
│   ├── Auth/       LoginView, ProfileSetupView
│   ├── Home/       RunnerHomeView (오늘 거리 + 현재 위치 지도, 최근 러닝)
│   ├── Running/    RunView, RunSession, RunResultView, RunDetailView, RouteMapView
│   ├── Records/    RunStatsView(주·월·년 차트), RunListView, StatsEngine
│   ├── Badges/     BadgesView(레벨·챌린지·최고 기록·뱃지), BadgeEarnedToast
│   ├── Canvas/     런꾸 (Phase 6 예정)
│   └── Settings/   SettingsView, ProfileEditView, VoiceSettingsView
├── Components/   PrimaryButton, StatLabel, AppleSignInButton, Keyboard, ProfileRows
├── Assets.xcassets/Badges/  뱃지 일러스트 19개
└── Info.plist    배열 키(백그라운드 위치·오디오, URL 스킴)
RunCanvasTests/    유닛 테스트 (순수 함수·DTO·세션)
RunCanvasUITests/  시뮬레이터 화면 흐름 + 스크린샷 (런치 인자 -uiTestSkipLogin / -uiTestReset)
docs/              supabase/schema.sql, superpowers/plans/(MVP 플랜 — 진행 상황·남은 태스크), design/
```

Xcode 동기화 폴더라 Finder에서 폴더·파일을 만들면 프로젝트에 자동 반영됩니다.

## 다른 Apple 계정으로 실기기 빌드 (팀원용)

서명 Team·Bundle ID는 `Config/Base.xcconfig`에 있고, 같은 폴더의 `Local.xcconfig`(gitignore)가 있으면 그 값으로 덮어씁니다. **Xcode의 Signing & Capabilities에서 Team을 직접 바꾸지 마세요** — pbxproj에 기록돼 충돌납니다.

1. Xcode → Settings → Accounts → `+` → 본인 Apple ID 추가 (무료 계정이면 "Personal Team" 생성됨)
2. 팀 ID 확인: 유료 계정이면 developer.apple.com → Membership details의 Team ID(10자리). 무료 계정이면 Signing & Capabilities에서 Team을 잠깐 본인 팀으로 바꾼 뒤 `git diff`로 `DEVELOPMENT_TEAM = XXXXXXXXXX` 값을 복사하고 `git checkout -- RunCanvas.xcodeproj/project.pbxproj`로 되돌립니다
3. `Config/Local.xcconfig` 생성:
   ```
   DEVELOPMENT_TEAM = XXXXXXXXXX
   PRODUCT_BUNDLE_IDENTIFIER = xxx.<본인이름>.RunCanvas
   ```
4. 아이폰 개발자 모드 켜고 연결 → ⌘R → 설정 → 일반 → VPN 및 기기 관리 → 개발자 앱 신뢰
5. Apple 로그인을 쓰려면 본인 번들 ID를 Supabase Apple 프로바이더 Client IDs에 추가해야 합니다 (동하에게 요청)

무료 Personal Team은 앱이 7일마다 만료되므로 다시 ⌘R 하면 됩니다. HealthKit은 되지만 App Groups·iCloud·푸시는 유료 계정이 필요합니다.
