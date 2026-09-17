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
├── Models/       Run(SwiftData, ownerID로 계정별), RoutePoint, RunDTO(서버 사본), Profile, Badge, Level, Challenge,
│                 Course(공유 코스), TrainingProgram(내장 + 사용자 제작)
├── Services/     Supabase, AuthService, ProfileService, SyncService, LocationService, HealthService, VoiceCoach,
│                 RunMath, BadgeEngine, BadgeStore, ChallengeEngine, CourseService, CourseGeometry, TrainingStore
├── Features/     화면 묶음별 폴더
│   ├── Onboarding/ SplashView
│   ├── Auth/       LoginView, ProfileSetupView
│   ├── Home/       RunnerHomeView (오늘 거리 + 현재 위치 지도, 최근 러닝)
│   ├── Running/    RunCoordinator(앱 수명 세션·워치 연동), RunView, RunSession, RunResultView, RunDetailView, RouteMapView
│   ├── Records/    RunStatsView(주·월·년 차트), RunListView, StatsEngine
│   ├── Badges/     BadgesView(레벨·챌린지·최고 기록·뱃지), BadgeEarnedToast
│   ├── Courses/    러닝 코스 공유 (목록·지도 탐색, 등록, 따라뛰기)
│   ├── Marathon/   마라톤 일정 (6시간마다 GitHub Actions 로 동기화한 Supabase 표를 읽는다)
│   ├── Training/   트레이닝 프로그램 (내장 3종 + 직접 만들기, 세션 진행)
│   ├── Recap/      이달의 러닝 정산
│   ├── Canvas/     런꾸 (배경·기록 선택, 스티커 편집, 이미지 저장·공유)
│   └── Settings/   SettingsView, ProfileEditView, VoiceSettingsView
├── Components/   PrimaryButton, SecondaryButton, StatLabel, ChipRow, FilterMenuPill, AppleSignInButton,
│                 Keyboard, ProfileRows
├── Assets.xcassets/Badges/  뱃지 일러스트 19개
└── Info.plist    배열 키(백그라운드 위치·오디오, URL 스킴)
RunCanvasTests/    유닛 테스트 (순수 함수·DTO·세션)
RunCanvasUITests/  시뮬레이터 화면 흐름 + 스크린샷 (런치 인자 -uiTestSkipLogin / -uiTestReset / -uiTestSkipHealth)
scripts/uitest.sh  UI 테스트 실행기 — 시뮬레이터 위치 권한을 허용한 뒤 xcodebuild 를 돌린다
scripts/sync_marathons.py  마라톤 일정 수집 → Supabase (`.github/workflows/sync-marathons.yml` 이 6시간마다 실행)
docs/              supabase/schema.sql, superpowers/plans/(MVP 플랜 — 진행 상황·남은 태스크), design/
```

Xcode 동기화 폴더라 Finder에서 폴더·파일을 만들면 프로젝트에 자동 반영됩니다.

UI 테스트는 `scripts/uitest.sh` 로 돌리세요. 시뮬레이터에 위치 권한이 한 번 "거부"로 남으면
권한 알럿이 다시 뜨지 않아 러닝이 시작되지 않고, 테스트는 그 상태를 스스로 되돌릴 수 없습니다.

```
scripts/uitest.sh                                                   # 전체
scripts/uitest.sh "iPhone 17 Pro" -only-testing:RunCanvasUITests    # 화면 흐름만
```

**화면 톤**: 배경은 시스템색(흰/검정) + 회색 8% 카드(`Color.card`). 설정류 `List`는 `.appListTone()`. 앱 틴트는 흑백, 레벨 컬러는 `PrimaryButton`·홈 러닝 시작 버튼에만 (`Components/Theme.swift`).

## 다른 Apple 계정으로 실기기 빌드 (팀원용)

공식 배포 서명 Team·Bundle ID(다은)는 `Config/Base.xcconfig`에 있고, 같은 폴더에 `Local.xcconfig`(gitignore)를 만들면 개발자별 값으로 덮어씁니다. 앱·워치·테스트 번들 ID는 전부 `APP_BUNDLE_ID` 하나에서 파생됩니다. **`Base.xcconfig`와 Xcode의 Signing & Capabilities Team은 건드리지 마세요** — pbxproj에 개인 팀 ID가 박혀 상대방 빌드가 깨집니다.

1. Xcode → Settings → Accounts → `+` → 본인 Apple ID 추가
2. 팀 ID 확인: developer.apple.com → Membership details의 Team ID(10자리)
3. `Config/Local.xcconfig` 생성 (딱 두 줄):
   ```
   DEVELOPMENT_TEAM = XXXXXXXXXX
   APP_BUNDLE_ID = com.<본인이름>.RunCanvas
   ```
4. 아이폰 개발자 모드 켜고 연결 → ⌘R → 설정 → 일반 → VPN 및 기기 관리 → 개발자 앱 신뢰
5. Apple 로그인을 쓰려면 본인 번들 ID를 Supabase Apple 프로바이더 Client IDs에 추가해야 합니다 (프로젝트 관리자에게 요청)

무료 Personal Team은 앱이 7일마다 만료되므로 다시 ⌘R 하면 됩니다. HealthKit은 되지만 App Groups·iCloud·푸시는 유료 계정이 필요합니다.

### `git pull` 후 Team·Provisioning 빌드 오류

Pull 직후 아래 오류가 나타나면 코드 문제가 아니라 Xcode가 `Config/Base.xcconfig`의 다른 팀원 서명 값을 사용하고 있는 상태입니다.

- `No Account for Team "..."`
- `No profiles for '...' were found`
- iPhone 앱은 빌드되지만 Watch 앱의 provisioning profile을 찾지 못함

다음 순서로 복구합니다.

1. `Config/Local.xcconfig`가 있는지 확인하고, 없다면 생성합니다.
2. 파일에는 본인 값 두 줄만 입력합니다. `PRODUCT_BUNDLE_IDENTIFIER`가 아니라 `APP_BUNDLE_ID`를 사용해야 iPhone·Watch·테스트 Bundle ID가 함께 변경됩니다.
   ```xcconfig
   DEVELOPMENT_TEAM = 본인_TEAM_ID
   APP_BUNDLE_ID = com.본인이름.RunCanvas
   ```
3. Xcode의 `Signing & Capabilities`에서 Team이나 Bundle Identifier를 직접 바꾸지 않습니다. 직접 변경하면 `project.pbxproj`에 개인 값이 기록되어 다른 팀원의 빌드가 깨집니다.
4. 이미 Signing 탭을 변경했다면 `git diff`로 `RunCanvas.xcodeproj/project.pbxproj`와 `RunCanvas/Info.plist`를 확인합니다. 서명 값 추가나 plist 키 순서 변경뿐일 때만 해당 변경을 되돌립니다. 의도적으로 작업한 변경이 섞여 있으면 파일 전체를 되돌리지 않습니다.
5. Xcode에서 `Product → Clean Build Folder`를 실행한 뒤 다시 빌드합니다.

`Config/Local.xcconfig`는 gitignore되므로 일반적인 `git pull`, 브랜치 전환, 병합으로 삭제되지 않습니다. 단, `git clean -fdx`는 gitignore된 파일까지 삭제하므로 사용하지 않습니다. 새로 클론하거나 다른 Mac에서 작업할 때는 이 파일을 다시 만들어야 합니다.
