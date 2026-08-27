# RunCanvas MVP 1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**작성:** 2026-08-25 · **갱신:** 2026-08-27 (Phase 0·1·2·5 완료 반영, 남은 Phase 3·4·6·7을 현재 코드 기준으로 다시 씀)

**Goal:** 스트라바식 러닝 앱 MVP 1.0 — 소셜 로그인, GPS 러닝 기록·저장, 심박수, 기록 통계, 레벨/뱃지, 런꾸(기록 이미지 꾸미기·공유)를 iOS 앱 하나로 완성한다.

**Architecture:** 오프라인 우선. 러닝 기록은 SwiftData(폰 로컬)가 원본이고 Supabase는 계정·프로필·서버 백업·2.0 챌린지용 사본이다. 순수 계산(페이스·칼로리·뱃지·챌린지)은 `RunMath`/`BadgeEngine`/`ChallengeEngine` 같은 값 타입 함수로 분리해 유닛 테스트하고, 화면은 `Features/<기능>/` 폴더에 View + 상태 객체를 함께 둔다. 모든 기록·뱃지는 `ownerID`(로그인 계정)로 분리되어 한 폰에서 여러 계정을 써도 섞이지 않는다.

**Tech Stack:** SwiftUI, SwiftData, Observation, CoreLocation, MapKit(`Map` + `MapPolyline` + `Annotation`), HealthKit(`HKAnchoredObjectQuery`, `HKWorkoutBuilder`), Swift Charts, PhotosUI, `ImageRenderer`, AuthenticationServices(Sign in with Apple), CryptoKit(nonce), XCTest + XCUITest, **supabase-swift 2.x (유일한 외부 의존성)**.

**Spec:** 이 문서 §0 (와이어프레임 `RunCanvas` GoodNotes + 2026-08-25 기능 목록을 인라인 정리). 별도 스펙 파일 없음. 뱃지·챌린지 벤치마킹과 아이디어는 동하 개인 메모(MY_TODO.md)에 있음.

## Global Constraints

- iOS 18.5+, Xcode 26, `SWIFT_VERSION = 5.0`, SwiftUI만 (UIKit은 `ImageRenderer`·`UIImageWriteToSavedPhotosAlbum` 같은 브릿지에만).
- 외부 의존성은 `supabase-swift` 하나. 구글/카카오 네이티브 SDK 추가 금지 — Supabase OAuth(웹) 플로우 사용.
- 서명: `DEVELOPMENT_TEAM`·`PRODUCT_BUNDLE_IDENTIFIER`는 `Config/Base.xcconfig`에만. 팀원은 gitignore된 `Config/Local.xcconfig`로 덮어씀(다은: 유료 ADP, `com.daun1997.RunCanvas`). entitlements·capability에 팀 종속 식별자 하드코딩 금지 → `$(PRODUCT_BUNDLE_IDENTIFIER)` 기반. Xcode Signing 탭에서 Team 변경 금지.
- Supabase Apple 프로바이더 Client IDs에 팀원 번들 ID가 있어야 그 폰에서 Apple 로그인이 됨 (현재 `name.dongharyu.RunCanvas, name.daun.RunCanvas, com.daun1997.RunCanvas`).
- git-flow: `feature/<기능>` → PR → `develop`. 커밋 메시지에 AI 작성 문구 없음. `main`/`develop` 직접 푸시 금지. Xcode가 pbxproj를 재정렬한 내용 없는 변경은 커밋하지 말고 되돌린다.
- 빈 폴더에 `.gitkeep` 금지 (Xcode 동기화 폴더가 리소스로 복사해 빌드 깨짐). 폴더는 첫 파일과 함께 생성.
- Info.plist 키: 문자열 키는 pbxproj `INFOPLIST_KEY_*`, 배열 키(`UIBackgroundModes`, `CFBundleURLTypes`)는 `RunCanvas/Info.plist` 파일.
- UI 문구 한국어. 앱 틴트는 흑백(`.tint(.primary)`), 카드 모서리 14, 설정류는 네이티브 인셋 그룹 `List`.
- 테스트: `xcodebuild test -project RunCanvas.xcodeproj -scheme RunCanvas -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO` (유닛 + UI). 새 순수 함수는 유닛 테스트, 새 화면 흐름은 `RunCanvasUITests`에 스크린샷 테스트 하나를 남긴다. 로그인 없이 화면을 띄우려면 DEBUG 런치 인자 `-uiTestSkipLogin`(고정 테스트 계정) · `-uiTestReset`(그 계정 데이터 초기화).

---

## §0. 스펙 (와이어프레임 + 기능 목록 정리)

### MVP 1.0 기능

| # | 기능 | 와이어프레임 | 상태 (2026-08-27) |
|---|---|---|---|
| F1 | 회원가입/로그인 — 구글·카카오·애플 | 스플래시 → 로그인 | **완료** — `LoginView`(Apple 기본 버튼 + 구글·카카오), 계정 연결/해제, 탈퇴 |
| F2 | 마이페이지 — 닉네임·키·체중·프로필 이미지·로그아웃 | 러닝 설정 화면 | **완료** — `SettingsView` + `ProfileEditView`, 첫 로그인 `ProfileSetupView` |
| F3 | 러닝 시작 → GPS 기록 → 일시정지 → 종료 | 홈 Run Start, 러닝 중 | **완료** — `RunView` + `RunSession` + `LocationService`(백그라운드, GPS 튐 필터) |
| F4 | 기록 저장 — 거리/시간/페이스/칼로리 계산 | 러닝 종료 | **완료** — `Run`(SwiftData, `ownerID`), `RunMath` |
| F5 | 러닝 상세 — 지도 경로 + 수치 | 러닝 상세 | **완료** — `RunResultView`/`RunDetailView`, NRC 스타일 `RouteMapView` |
| F6 | 심박수 (HealthKit, 워치가 기록한 값) | 러닝 중 BPM | **남음 → Phase 3** (`RunSession.heartRate`·`Run.averageHeartRate` 자리만 있음) |
| F7 | 나의 기록 — 목록, 주/월/년 통계, 그래프 | 나의 기록 | **완료** — `RunStatsView`(Swift Charts) + `RunListView`, `StatsEngine` |
| F8 | 홈 — 최신 기록 카드, 배경 지도+현재 위치, Run Start | 홈 | **완료** — 오늘 거리 + 현재 위치 지도 카드, 최근 3개, 전체 보기 |
| F9 | 러닝 레벨/뱃지 부여 | 프로필 | **완료** — 레벨 7단계, 뱃지 19종(일러스트), 로컬 챌린지 4개, 획득 토스트 |
| F10 | 런꾸 — 배경 이미지 선택 → 기록 선택 → 스티커 편집 → 저장/공유 | 런꾸 1~4 | **남음 → Phase 6** (`RunDecorateView` 껍데기) |
| F11 | 기록 이미지 저장 및 공유 | 런꾸 4 | **남음 → Phase 6** |
| F12 | 음성 안내 — 러닝 중 거리·시간·페이스 읽어주기 (NRC식, 2026-08-27 추가 결정) | 러닝 중 | **완료** — `VoiceCoach`(내장 TTS 기본 음성, 음악 덕킹), 설정에서 켬/끔·간격 |
| — | 서버 동기화 · TestFlight | — | 동기화 **완료**(7.1) · 출시 준비 **남음 → Phase 7.2** |

### MVP 2.0 (이 플랜 범위 밖, 스키마만 대비)

서버 챌린지(친구·단체, 뱃지 부여), 한국 마라톤 일정 뷰, 런꾸 월말/연말정산, Apple Watch 앱, 다른 기기로 기록 복원(서버→로컬 다운로드).

### 확정된 설계 결정

1. **기록 원본 = SwiftData 로컬.** 러닝은 통신 없는 곳에서도 끝나야 하고 저장에 실패하면 안 된다. Supabase `runs`엔 종료 후 업로드(실패 시 다음 기회에 재시도), 서버에만 있는 기록은 로그인·앱 활성화 때 다운로드(다른 기기·재설치 복원, 2026-08-27 1.0에 포함).
2. **인증 = Supabase Auth, 소셜만.** 애플은 네이티브(`signInWithIdToken`, .p8 불필요), 구글·카카오는 `signInWithOAuth`(리다이렉트 `runcanvas://auth-callback`). 이메일/비밀번호 로그인은 안 한다. Apple "이메일 가리기"로 생긴 중복 계정은 **계정 연결**(`linkIdentity`, manual linking ON)로 대응. 첫 로그인 후 `profiles` 행이 없으면 프로필 설정(닉네임·키·체중 필수).
3. **계정별 분리.** `Run.ownerID`와 `BadgeStore`의 계정별 키(`earnedBadgeDates.<uid>`)로, 화면의 `@Query`는 항상 `#Predicate { $0.ownerID == owner }`. 로그아웃해도 기록은 폰에 남고 같은 계정으로 다시 로그인하면 보인다. 탈퇴 시 그 계정의 Run·뱃지 캐시만 삭제.
4. **심박수는 읽기만.** 아이폰 단독으론 심박이 안 잡히고, 워치가 HealthKit에 쓴 샘플을 `HKAnchoredObjectQuery`로 실시간 구독한다. 종료 시 `HKWorkoutBuilder`로 러닝 워크아웃을 건강 앱에 저장. 워치 앱 자체는 2.0.
5. **레벨/뱃지 = 순수 함수 + 로컬 저장.** `BadgeEngine.earned(runs:)`는 기록 배열에서 계산, 획득 날짜는 `BadgeStore`(UserDefaults)에 계정별로 기록. 챌린지도 같은 방식(`ChallengeEngine`, 기간 키 `id@2026-08`). 서버 `user_badges`는 Phase 7에서 업로드만. 기록을 삭제해도 이미 딴 뱃지는 유지한다.
6. **GPS 품질.** 정확도 20m 초과·10초 넘은 캐시 위치·12 m/s 넘는 점프는 버린다(`LocationService`). 지도는 NRC 방식(채도 낮춘 지도, 흰 테두리 위 구간별 페이스 색, 시작·종료 점).
7. **런꾸 결과물은 사진 앱 + 앱 Documents.** 서버 업로드 없음(2.0 정산에서 필요해지면 그때).
8. 하단 탭은 `RootTabView` 하나(홈·기록·런꾸·설정). 화면 안 자체 탭바 금지.

### 폴더·파일 맵 (현재 형태, ✱ = 남은 Phase에서 생성/교체)

```
RunCanvas/
├── App/            RunCanvasApp, RootTabView, AppRouter(스플래시→로그인/프로필설정/탭, DEBUG 테스트 계정)
├── Models/         Run(@Model, ownerID), RoutePoint, RunDTO(+UserBadgeDTO), Profile, Badge, Level, Challenge, ✱Sticker
├── Services/       Supabase, AuthService, ProfileService, LocationService, RunMath,
│                   BadgeEngine, BadgeStore, ChallengeEngine, VoiceCoach(+VoiceCue), SyncService, ✱HealthService
├── Features/
│   ├── Onboarding/ SplashView
│   ├── Auth/       LoginView, ProfileSetupView
│   ├── Home/       RunnerHomeView(HomeContent @Query, 현재 위치 지도 카드, RunHistoryRow)
│   ├── Running/    RunView, RunSession, RunResultView, RunDetailView, RouteMapView(PaceSegment)
│   ├── Records/    RunStatsView(Swift Charts), RunListView, StatsEngine
│   ├── Canvas/     RunDecorateView(껍데기) → ✱CanvasFlowView, BackgroundPickerView, RunPickerView,
│   │               StickerEditorView, StickerCanvas, CanvasExportView
│   ├── Badges/     BadgesView(LevelCard·ChallengeRow·BestTile·BadgeCell·BadgeArt), BadgeEarnedToast
│   └── Settings/   SettingsView, ProfileEditView, VoiceSettingsView, ProfileHeader
├── Components/     PrimaryButton, StatLabel, AppleSignInButton(+AppleAuthorizer, AppleNonce), Keyboard, ProfileRows(AvatarView)
├── Assets.xcassets/Badges/  badge_<Badge.rawValue> 19개 (Gemini 일러스트, 획득=컬러/잠김=흑백은 코드 처리)
├── Info.plist      (배열 키 전용: UIBackgroundModes location, runcanvas:// 스킴, 사진 추가 권한)
└── RunCanvas.entitlements  applesignin, healthkit
RunCanvasTests/     RunMathTests, RunSessionTests, LocationServiceTests, BadgeEngineTests(+LevelTests),
                    ChallengeTests(+BadgeStoreTests), ProfileTests, StatsEngineTests, VoiceCoachTests, RunDTOTests — 50개
RunCanvasUITests/   RunFlowUITests(러닝 E2E + 스크린샷), BadgesScreenUITests, RecordsScreenUITests, VoiceSettingsUITests
docs/               supabase/schema.sql, design/badge-illustration-prompts.md, superpowers/plans/(이 문서)
Config/             Base.xcconfig (+ Local.xcconfig gitignore)
```

### 페이즈 순서와 담당

| Phase | 내용 | 의존 | 담당 | 상태 |
|---|---|---|---|---|
| 0 | 기반: 테스트 타깃, SPM, Supabase 프로젝트·스키마, Info.plist | — | 동하 | ✅ PR #5·#6·#7 |
| 1 | 러닝 코어: 모델·저장·경로·세션·결과·상세 | 0 | Claude | ✅ PR #16 |
| 2 | 로그인·프로필 (Supabase Auth/Storage) | 0 | 동하 | ✅ PR #8~#14 |
| 5 | 레벨/뱃지 + 로컬 챌린지 | 1 | Claude | ✅ PR #15·#16 |
| 3 | HealthKit 심박 + 워크아웃 저장 | 1 | 다은 | 남음 |
| 4 | 나의 기록 통계·홈 지도 | 1 | Claude | ✅ PR #18 |
| 6 | 런꾸 + 이미지 저장/공유 | 1 | 미정 (동하/Claude 또는 다은) | 남음 |
| 7 | 서버 동기화(7.1) + 출시 준비(7.2, TestFlight) | 1, 2 | 동하 | 7.1 ✅ PR #20 · 7.2 남음 |

3·6은 서로 파일이 안 겹쳐 병렬 가능. 7.2는 마지막. 각 Phase = PR 1~3개.

---

## 완료된 Phase 요약 (0 · 1 · 2 · 4 · 5 · 7.1)

원래 플랜과 달라진 점만 적는다. 코드가 문서이므로 세부 단계는 제거했다.

### Phase 0 — 기반 (PR #5·#6·#7)
- 테스트 타깃 `RunCanvasTests`·UI 테스트 타깃 `RunCanvasUITests`(pbxproj 직접 편집, ID `C0DE…`), 공유 스킴(Testables, `OS_ACTIVITY_MODE=disable`).
- supabase-swift 2.x, `Services/Supabase.swift`(publishable 키, `emitLocalSessionAsInitialSession: true`).
- Supabase 프로젝트 `kqakxyzssscoyppargws`(서울), `docs/supabase/schema.sql`: `profiles`(+`height_cm`)·`runs`·`user_badges` + RLS, `avatars` 버킷(읽기 공개, 본인 폴더 쓰기/수정/삭제), RPC `delete_own_account()`(security definer, `auth.users`만 삭제 — storage.objects는 트리거 때문에 DB에서 못 지우므로 아바타는 앱이 Storage API로 먼저 삭제).
- `RunCanvas/Info.plist` 배열 키, 위치·건강·사진 권한 문구.

### Phase 1 — 러닝 코어 (PR #16)
- `Run`: `id`(unique), `ownerID`, `startedAt/endedAt`, `distanceMeters`, `movingSeconds`, `calories`, `averageHeartRate/maxHeartRate`, `route: [RoutePoint]`(인라인), `syncedAt`, `decoratedImageFilename`. `badgeRun`으로 뱃지 엔진 입력 변환.
- `LocationService`(@Observable, 정확도·캐시·점프 필터, 백그라운드 업데이트), `RunSession`(idle/running/paused/finished, 날짜 차이로 경과 계산해 일시정지 제외, `finish(ownerID:weightKg:context:) -> Run`, `heartRate`/`recordHeartRate(_:)`는 Phase 3용 자리).
- `RunView`(즉시 시작, 종료 → `fullScreenCover`로 `RunResultView`), `RunResultView`(@Query 계정 기록으로 `BadgeStore.recordNewlyEarned`·`recordCompletedChallenges` → 토스트, "사진으로 꾸미기"는 Phase 6 TODO), `RunDetailView`, `RouteMapView`(NRC).
- 홈 `RunnerHomeView`: 오늘 거리, 러닝 시작, 최근 3개 → 상세. 자체 탭바 제거.
- UI 테스트 `RunFlowUITests`: `XCUIDevice.shared.location`으로 GPS 시뮬레이션 → 결과·홈·상세 스크린샷 첨부.

### Phase 2 — 로그인·프로필 (PR #8·#9·#10·#11·#12·#13·#14)
- `AuthService`(@MainActor @Observable): 구글·카카오 `signInWithOAuth`, Apple `signInWithIdToken`, `identities` + `linkGoogle/linkKakao/linkApple/unlink`, `signOut`, `deleteAccount()`(아바타 삭제 → RPC → 로컬 세션 정리 → `BadgeStore.reset(for:)` → 탈퇴 알럿). DEBUG `debugUserID`.
- `Profile`(id, nickname, weightKg, heightCm, avatarURL) + `ProfileService`(fetchMine/upsert/uploadAvatar).
- 화면: `AppRouter`, `LoginView`, `ProfileSetupView`(검증·포커스·키보드 툴바), `SettingsView`(인셋 그룹: 프로필 카드→`ProfileEditView`, 레벨과 뱃지, 러닝/앱 설정, 연결된 계정, 계정), `Components/Keyboard.swift`, `AppleSignInButton`+`AppleAuthorizer`.
- 외부 설정: Google OAuth(Testing, 테스트 사용자 2명), Kakao 비즈 앱(이메일 동의), Apple Services ID·Supabase Apple 패널.

### Phase 4 — 나의 기록·홈 (PR #18)
- `Features/Records/StatsEngine.swift`(순수 함수): `Period` 주/월/년, `summary`(합계·횟수·시간·평균 페이스), `buckets`(요일 7·일별·월 12, 빈 구간 0). 요일 라벨은 한글 고정 — 영어 로케일의 T/S 중복 라벨을 Swift Charts가 한 막대로 합치는 버그 회피.
- `RunStatsView`: 다은 레이아웃 유지 + `@Query(ownerID)`, 전체 기록 카드 4개, 기간 세그먼트 + `Chart(BarMark)`, 주간 목표(설정 `weeklyTargetDistance`) 진행, 최근 3개·전체 보기. `RunListView`: 전체 목록 + 스와이프 삭제(뱃지 유지).
- 홈: "오늘의 러닝" 카드 배경에 `Map(.userLocation)` + `UserAnnotation`(권한 요청은 러닝 화면에서만), 전체 보기, 러닝 시작 버튼 다크 모드 수정. 안 쓰던 `HomeView`/`RecordsView` 삭제.

### Phase 7.1 — 동기화 (PR #20)
- `Models/RunDTO.swift`(`runs` 컬럼 1:1, ISO 8601 문자열, route jsonb) + `UserBadgeDTO`. `Services/SyncService.pushPending(context:ownerID:)`: `syncedAt == nil` 기록 upsert → 성공 시 `syncedAt`, 뱃지 upsert. 실패는 조용히, 다음 기회 재시도.
- 호출: `AppRouter.syncIfPossible()`(로그인 로드 뒤 + `scenePhase == .active`), `RunResultView.task` → `SyncService.sync` = 업로드 → 다운로드. `AuthService.canSync`(실제 세션만, UI 테스트 계정 제외).
- 다운로드 `pullMissing`: 서버 `runs` 중 로컬에 없는 id 삽입(`RunDTO.makeRun`, `syncedAt` 표시), `user_badges` 획득 날짜 `BadgeStore.merge`(더 이른 날짜 유지). Postgres 가변 소수점 날짜는 `RunDTO.parseDate`.
- 서버 드라이런(동하 계정 RLS)으로 삽입·중복 upsert·뱃지 확인.

### 음성 안내 (PR #19, 플랜 외 추가)
- `Services/VoiceCoach.swift`: `AVSpeechSynthesizer`(ko-KR 기본 음성) + 오디오 세션 `.playback/.spokenAudio` + `duckOthers`(안내 중 음악 작아짐, 끝나면 복구), 설정 키 `voiceGuideEnabled/voiceGuideIntervalMeters`. `VoiceCue`는 문장 생성 순수 함수.
- `RunSession(coach:)`: 시작·일시정지·재개·종료 한 마디 + 설정 간격(500m/1km/2km)마다 거리·시간·페이스. 매초 틱의 `checkVoiceCue()`.
- `VoiceSettingsView`(설정 → 러닝 설정 → 음성 안내): 켬/끔, 간격(500m/1km/2km), 미리 듣기. `Info.plist` UIBackgroundModes에 `audio` 추가.
- 사용자 결정(2026-08-27): 음성은 기본 하나(Yuna). 목소리 선택·다른 언어·녹음 목소리는 2.0.

### Phase 5 — 레벨/뱃지 (PR #15·#16)
- `Level`(Tier yellow→volt 7단계, 0/50/250/1000/2500/5000/15000km), `Badge` 19종(거리·누적·연속·횟수·시간대, `imageName`/`symbolName` 폴백), `Challenge.all` 4개(주 3회, 월 50km, 월 8회, 월 10K).
- `BadgeEngine`(earned/progressValue/personalBests/longestDailyStreak), `ChallengeEngine`(status/periodKey), `BadgeStore`(계정별 획득 날짜·완료 챌린지, `reset(for:)`).
- `BadgesView(ownerID:)`(레벨 카드, 챌린지 진행바, 최고 기록 타일, 카테고리별 그리드), `BadgeArt`(일러스트/심볼), `BadgeEarnedToast`. 일러스트 19개는 Gemini로 생성해 배경 제거 후 에셋화(`docs/design/badge-illustration-prompts.md`).

---

## Phase 3 — HealthKit 심박 (태스크 레벨)

브랜치: `feature/heart-rate`. 담당 다은. **실기기 + 애플워치 필요** (시뮬레이터는 건강 앱에 수동 심박 샘플을 넣어 스트림만 확인).

이미 있는 것: entitlements `com.apple.developer.healthkit`, 권한 문구(`NSHealthShareUsageDescription`/`NSHealthUpdateUsageDescription`), `RunSession.heartRate`·`heartRateSamples`·`recordHeartRate(_:)`, `Run.averageHeartRate/maxHeartRate`, 결과·상세 화면의 "평균 BPM" 라벨(값 없으면 `--`).

### Task 3.1: HealthService
- Create `RunCanvas/Services/HealthService.swift`: `@Observable final class HealthService`
  - `var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }`
  - `func requestAuthorization() async throws` — read `HKQuantityType(.heartRate)`, share `HKObjectType.workoutType()`, `HKQuantityType(.distanceWalkingRunning)`, `HKQuantityType(.activeEnergyBurned)`.
  - `func startHeartRateStream(since: Date, onSample: @escaping (Double) -> Void)` — `HKAnchoredObjectQuery(type:predicate: HKQuery.predicateForSamples(withStart: since, end: nil), anchor: nil, limit: HKObjectQueryNoLimit)` + `updateHandler`, 단위 `HKUnit.count().unitDivided(by: .minute())`, 콜백은 메인 큐로.
  - `func stopHeartRateStream()`
  - `func saveWorkout(_ run: Run) async throws` — `HKWorkoutConfiguration(activityType: .running, locationType: .outdoor)`, `HKWorkoutBuilder` `beginCollection(at: run.startedAt)` → 거리·칼로리 `HKCumulativeQuantitySample` `add` → `endCollection(at: run.endedAt)` → `finishWorkout()`. 경로는 `HKWorkoutRouteBuilder`로 `route` 좌표 삽입(선택, 있으면 건강 앱 지도에 뜸).
- 완료 조건: 워치에서 워크아웃 켜고 앱 러닝 시작 → 러닝 화면 BPM 갱신. 종료 후 건강 앱에 러닝 워크아웃이 보임.

### Task 3.2: RunSession 연결
- `RunSession.init(location:health:now:)`에 `health: HealthService? = nil` 추가 — 기존 `RunSessionTests`는 nil 그대로.
- `start()`에서 `health?.startHeartRateStream(since: startedAt) { [weak self] in self?.recordHeartRate($0) }`, `finish(...)`에서 `stopHeartRateStream()` 후 `Task { try? await health?.saveWorkout(run) }`. `Run.averageHeartRate/maxHeartRate`는 `finish`가 `heartRateSamples`로 이미 채운다 — 손댈 것 없음. 러닝 화면 BPM 라벨(`RunView.swift:42`)도 `session.heartRate`를 이미 본다.
- `RunView.onAppear`(또는 세션 start 직전)에서 `try? await health.requestAuthorization()` — 위치 권한 알럿과 겹치지 않게 위치 권한 뒤에.
- 테스트: `RunSessionTests`에 `recordHeartRate` 3개 → finish 후 평균·최대 검증(HealthService 불필요). `HealthService`는 HealthKit 실기기 의존이라 유닛 테스트 대상 아님 — 실기기 확인으로 대체.
- UI 테스트: 시뮬레이터엔 심박이 없으니 기존 `RunFlowUITests`가 그대로 통과하는지만 확인(권한 알럿이 추가되면 springboard 처리 추가).

---

## Phase 4 — 나의 기록·홈 — ✅ 완료 (PR #18, 위 요약 참고. 아래는 원래 태스크)

브랜치: `feature/records`. 현재 `RunStatsView`(218줄)는 하드코딩 카드(전체 기록·이번 주·최근 기록) — 레이아웃은 유지하고 데이터만 실데이터로 바꾼다.

참고 패턴: 계정 기록 조회는 `RunnerHomeView.swift`의 `HomeContent`처럼 `init(ownerID: UUID?)`에서 `_runs = Query(filter: #Predicate<Run> { $0.ownerID == owner }, sort: \Run.startedAt, order: .reverse)`. `ownerID`는 `@Environment(AuthService.self) auth.userID`. 포맷은 `RunMath.formatKm/formatDuration/formatPace`. 최장 거리·최고 페이스·연속일은 `BadgeEngine.personalBests`/`longestDailyStreak`가 이미 계산한다.

### Task 4.1: StatsEngine + 테스트
- Create `RunCanvas/Features/Records/StatsEngine.swift`(순수 함수, `BadgeRun` 입력으로 SwiftData와 분리):
  - `enum Period: String, CaseIterable { case week = "주", month = "월", year = "년" }`
  - `struct Summary { totalMeters: Double; count: Int; totalSeconds: Int; avgPaceSecondsPerKm: Double? }`
  - `struct Bucket: Identifiable { id: String; label: String; distanceMeters: Double }`
  - `static func summary(runs: [BadgeRun], period: Period, now: Date, calendar: Calendar = .current) -> Summary` — 현재 기간(이번 주 월~일, 이번 달, 올해)만.
  - `static func buckets(runs:period:now:calendar:) -> [Bucket]` — 주=요일 7개(월~일), 월=일별, 년=월 12개. 빈 구간도 0으로 포함(차트 x축 고정).
- Test `RunCanvasTests/StatsEngineTests.swift`: 이번 주 3건 합계·평균 페이스, 지난 주 제외, 빈 배열 → 0·nil, 년 버킷 12개.

### Task 4.2: RunStatsView 실데이터 + 차트
- `RunStatsView`: `init(ownerID:)` @Query(위 패턴), 상단 "전체 기록" 카드 4개(총 거리·횟수·평균 페이스·최장 거리)는 전체 기록으로, `Picker`(주/월/년, segmented) 아래 큰 숫자(기간 총 km) + `StatLabel` 3개(횟수·평균 페이스·시간) + `Chart { BarMark(x: .value("기간", bucket.label), y: .value("km", bucket.distanceMeters / 1000)) }`(`import Charts`).
- 기록 없음 상태: `ContentUnavailableView("아직 기록이 없어요", systemImage: "figure.run")`.
- Create `RunListView.swift`(같은 폴더): 날짜 역순 전체 목록(`RunHistoryRow` 재사용) → `RunDetailView`. 스와이프 삭제 → `context.delete(run)` (뱃지는 유지 — 결정 5). `RunStatsView` 하단 "전체 보기" 링크.
- UI 테스트: `RecordsScreenUITests` — `-uiTestSkipLogin`으로 기록 탭 → 스크린샷 1장 (러닝 E2E 뒤에 실행하면 기록 1건이 있는 상태).

### Task 4.3: 홈 마무리
- `RunnerHomeView`: "오늘의 러닝" 숫자 뒤 배경으로 `Map(position: .constant(.userLocation(fallback: .automatic))) { UserAnnotation() }` + `.mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))` + `.mapControlVisibility(.hidden)` + 위에 그라데이션 오버레이(글자 가독성). onAppear에 `LocationService.requestPermission()`(이미 러닝 화면에서 요청하므로 홈에서는 권한 있을 때만 지도 표시해도 됨).
- 최근 러닝 카드 탭 → 상세는 이미 됨. "전체 보기" → `RunListView`.
- 완료 조건: 기록 탭 숫자·차트가 실제 기록과 일치, 스와이프 삭제 후 홈·기록·뱃지 화면 모두 갱신.

---

## Phase 6 — 런꾸 (태스크 레벨)

브랜치: `feature/canvas`. 담당 미정. 와이어프레임 런꾸 1~4 순서 그대로 4화면. 진입점 2개: 탭 "런꾸"(`RootTabView` → 현재 `RunDecorateView()`)와 `RunResultView`의 "사진으로 꾸미기"(`RunResultView.swift:39` TODO, 여기선 기록 선택을 건너뜀).

### Task 6.1: 플로우 + 배경 선택 (런꾸 1)
- Create `Features/Canvas/CanvasFlowView.swift`: `NavigationStack` + `@State var background: CanvasBackground?` (`enum CanvasBackground { case preset(Int), photo(UIImage) }`), `@State var run: Run?`. `init(run: Run? = nil)`.
- Create `BackgroundPickerView.swift`: 기본 배경 6종(단색·그라데이션, `Assets.xcassets/Canvas/`) 그리드 + `PhotosPicker`(`preferredItemEncoding: .compatible`, 라이브포토 제외 — `ProfileEditView` 패턴) + 카메라(`UIImagePickerController` 래퍼 `CameraPicker`).
- `RootTabView` 런꾸 탭 → `CanvasFlowView()`, `RunResultView` "사진으로 꾸미기" → `CanvasFlowView(run: run)`을 `fullScreenCover`로. `RunDecorateView` 삭제.

### Task 6.2: 기록 선택 (런꾸 2)
- Create `RunPickerView.swift`: 계정 기록 `@Query`(Phase 4 패턴) 목록(날짜·거리·시간, `RunHistoryRow`) → 선택 → `run` 세팅. `run != nil`로 들어오면 이 화면은 건너뛴다.

### Task 6.3: 스티커 편집 (런꾸 3)
- Create `Models/Sticker.swift`: `struct Sticker: Identifiable { id: UUID; kind: Kind; position: CGPoint; scale: CGFloat; opacity: Double; fontStyle: FontStyle }`, `enum Kind { case distance, time, pace, date, calories, heartRate, route, badge(Badge), text(String) }`, `enum FontStyle: CaseIterable { case bold, rounded, mono }`.
- Create `StickerCanvas.swift`: 배경 이미지(정사각 또는 4:5) 위에 `ForEach(stickers)` — 각 스티커 `DragGesture` + `MagnifyGesture`. `route`는 `Path`로 경로 실루엣(`RoutePoint` → 정규화 좌표), `badge`는 `BadgeArt(badge:isEarned: true)`. **이 뷰가 렌더 대상**(편집 UI와 분리, 제스처는 `isEditing` 플래그로 끔).
- Create `StickerEditorView.swift`: `StickerCanvas` + 하단 툴바(스티커 추가 메뉴 — 거리/시간/페이스/날짜/칼로리/심박/경로/뱃지(획득한 것만)/텍스트, 선택 스티커 불투명도 슬라이더, 글자 스타일 3종, 텍스트 입력은 `alert` 텍스트필드).

### Task 6.4: 저장·공유 (런꾸 4)
- Create `CanvasExportView.swift`: 미리보기 + 버튼 4개 — **사진 앱 저장**(`ImageRenderer(content: StickerCanvas(...))`, `scale = 3`, `UIImageWriteToSavedPhotosAlbum`; `NSPhotoLibraryAddUsageDescription`은 이미 있음), **공유**(`ShareLink(item: Image(uiImage:), preview:)`), **다시 수정**(pop), **앱에 저장**(JPEG를 `Documents/canvas/<run.id>.jpg`에 쓰고 `run.decoratedImageFilename` 세팅).
- `RunDetailView`: `decoratedImageFilename`이 있으면 지도 아래에 꾸민 이미지 표시.
- 완료 조건: 사진 앱에 3배 해상도 이미지, 공유 시트 동작, 앱 재시작 후 상세에서 꾸민 이미지 표시. UI 테스트 `CanvasScreenUITests` — 배경 프리셋 선택 → 편집 화면 스크린샷.

---

## Phase 7 — 동기화 + 출시 준비 (태스크 레벨)

담당 동하. 7.1은 ✅ 완료(PR #20, `feature/sync`). 7.2는 3·6 머지 뒤 마지막에 (`release/1.0` 브랜치).

### Task 7.1: SyncService — ✅ 완료
- Create `Models/RunDTO.swift`: `runs` 테이블 컬럼과 1:1 `Codable` — `id, user_id, started_at, ended_at, distance_m, moving_s, avg_hr, max_hr, calories, route`(`[["lat":..,"lon":..,"t":..]]`, ISO8601). `init(run: Run)`(`user_id = run.ownerID`).
- Create `Services/SyncService.swift`: `static func pushPending(context: ModelContext, ownerID: UUID) async` — `FetchDescriptor<Run>(predicate: #Predicate { $0.ownerID == ownerID && $0.syncedAt == nil })` → `supabase.from("runs").upsert(dtos).execute()` → 성공한 것만 `syncedAt = .now`. 뱃지는 `BadgeStore.earnedDates(for: ownerID)` → `user_badges` upsert(`badge = rawValue, earned_at`).
- 호출 시점: `RunResultView` 등장 시, `RunCanvasApp`의 `scenePhase == .active`. 오프라인이면 조용히 실패(다음 기회에 재시도). 로그인 안 됐거나 DEBUG 테스트 계정이면 스킵.
- 완료 조건: 비행기 모드로 러닝 종료 → 네트워크 켜고 홈 복귀 → 대시보드 `runs`에 행 생성, 두 번 실행해도 중복 없음. 테스트: `RunDTOTests`(인코딩 키·route 변환).

### Task 7.2: 출시 준비
- 앱 아이콘(1024 + 다크/틴트), 런치 스크린 색, `MARKETING_VERSION`(현재 1.0)·빌드 번호.
- 권한 문구 재검토: 위치(러닝 중 백그라운드 인디케이터 문구 포함)·건강 읽기/쓰기·사진 추가.
- **Google OAuth 동의 화면 Testing → Publish**(지금은 테스트 사용자 2명만 로그인 가능), **카카오 앱 아이콘 교체**(임시 PNG), 카카오 비즈 앱 검수 항목 확인.
- App Store Connect 앱 등록(번들 `name.dongharyu.RunCanvas`, 동하 계정) → Archive → TestFlight 내부 테스트(다은 = 내부 테스터). 업로드는 번들 소유자인 동하만.
- 심사 대비 체크: Apple 로그인 ✅, 계정 삭제 ✅(5.1.1(v)), 개인정보 처리방침 URL(위치·건강 데이터 언급) 준비, 건강 데이터는 광고·제3자 공유 없음 명시.

---

## MVP 2.0 백로그 (착수 시 별도 플랜)

- 서버 챌린지: `challenges`, `challenge_participants` 테이블, 기간·목표, 친구·단체 참여, 완료 시 뱃지 부여(서버 함수). 지금의 로컬 챌린지(`Challenge.all`)를 서버 정의로 교체.
- 뱃지 획득 연출 풀스크린(NRC식) + 획득 뱃지 공유 카드, 런꾸 뱃지 스티커(6.3에 일부 선반영).
- 음성 안내 2.0: 목소리 선택(Azure 한국어 10개·클로바 등으로 조각 음성 팩 생성해 앱에 내장 — 대본은 숫자 0~59·단위·시작/종료 약 150조각), 영어, 가이드 런/코칭, 시간 기준 안내, 목표 페이스 대비 빠름/느림 알림, 워치.
- 챌린지 트로피: 완료한 챌린지를 월별 트로피로 모아 보기(스트라바식). 서버 챌린지와 같이 설계 — 완료 키는 이미 `BadgeStore.completedChallenges`에 `id@2026-08`로 저장 중.
- 한국 마라톤 일정: 정적 JSON(`Resources/marathons.json`, 월 1회 갱신) → 목록/캘린더 뷰. 외부 API 없음.
- 런꾸 월말/연말정산: `runs` 집계 + 해당 기간 `decoratedImageFilename` 콜라주 → `ImageRenderer`.
- Apple Watch 앱: `HKWorkoutSession`으로 워치 단독 러닝, App Groups(`group.$(PRODUCT_BUNDLE_IDENTIFIER)`)로 공유.
- Apple 웹 로그인(.p8) 필요 시. (서버 → 로컬 복원은 1.0에 포함됨)

---

## Self-Review

- **스펙 커버리지**: F1·F2→Phase 2 ✅, F3·F4·F5→Phase 1 ✅, F9→Phase 5 ✅, F6→3.1/3.2, F7→4.1/4.2, F8→4.3(지도), F10→6.1~6.3, F11→6.4, 동기화·출시→7.1/7.2. 2.0 항목은 백로그.
- **플레이스홀더**: 완료 Phase는 요약만(코드가 원본). 남은 Phase 3·4·6·7은 태스크 레벨(파일·시그니처·완료 조건)이며 착수 시 단계별로 상세화한다 — "TBD"는 없음.
- **타입 일관성(현재 코드 기준)**: `RoutePoint(latitude:longitude:timestamp:)`, `Run.movingSeconds`, `Run.badgeRun -> BadgeRun`, `RunMath.paceSecondsPerKm(distanceMeters:seconds:)`/`formatKm`/`formatDuration`/`formatPace`, `RunSession.finish(ownerID:weightKg:context:)`, `RunSession.recordHeartRate(_:)`, `StatLabel(title:value:)`, `PrimaryButton(title:systemImage:action:)`, `RunDetailView(run:)`, `RunResultView(run:)`, `RouteMapView(route:)`, `BadgesView(ownerID:)`, `BadgeArt(badge:isEarned:size:)`, `BadgeStore.earnedDates(for:)`/`reset(for:)`, `BadgeEngine.personalBests`/`longestDailyStreak`, `AuthService.userID`.
