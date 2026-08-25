# RunCanvas MVP 1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 스트라바식 러닝 앱 MVP 1.0 — 소셜 로그인, GPS 러닝 기록·저장, 심박수, 기록 통계, 레벨/뱃지, 런꾸(기록 이미지 꾸미기·공유)를 iOS 앱 하나로 완성한다.

**Architecture:** 오프라인 우선. 러닝 기록은 SwiftData(폰 로컬)가 원본이고 Supabase는 계정·프로필·서버 백업·2.0 챌린지용 사본이다. 순수 계산(페이스·칼로리·뱃지)은 `RunMath`/`BadgeEngine` 같은 값 타입 함수로 분리해 유닛 테스트하고, 화면은 `Features/<기능>/` 폴더에 View + ViewModel을 함께 둔다.

**Tech Stack:** SwiftUI, SwiftData, CoreLocation, MapKit(`MapPolyline`), HealthKit(`HKWorkoutBuilder`), Swift Charts, PhotosUI, `ImageRenderer`, AuthenticationServices(Sign in with Apple), **supabase-swift 2.x (유일한 외부 의존성)**.

**Spec:** 이 문서 §0 (와이어프레임 `RunCanvas` GoodNotes + 2026-08-25 기능 목록을 인라인 정리). 별도 스펙 파일 없음.

## Global Constraints

- iOS 18.5+, Xcode 26, `SWIFT_VERSION = 5.0`, SwiftUI만 (UIKit은 `ImageRenderer`·`UIImageWriteToSavedPhotosAlbum` 같은 브릿지에만).
- 외부 의존성은 `supabase-swift` 하나. 구글/카카오 네이티브 SDK 추가 금지 — Supabase OAuth(웹) 플로우 사용.
- 서명: `DEVELOPMENT_TEAM`·`PRODUCT_BUNDLE_IDENTIFIER`는 `Config/Base.xcconfig`에만. entitlements·capability에 팀 종속 식별자(`name.dongharyu.…`) 하드코딩 금지 → `$(PRODUCT_BUNDLE_IDENTIFIER)` 기반. Xcode Signing 탭에서 Team 변경 금지.
- **Sign in with Apple capability는 다은 ADP 승인 후 추가** (무료 계정은 서명 실패). Phase 2의 Apple 로그인 태스크가 이 게이트에 걸린다.
- git-flow: `feature/<기능>` → PR → `develop`. 커밋 메시지에 AI 작성 문구 없음. `main`/`develop` 직접 푸시 금지.
- 빈 폴더에 `.gitkeep` 금지 (Xcode 동기화 폴더가 리소스로 복사해 빌드 깨짐). 폴더는 첫 파일과 함께 생성.
- Info.plist 키: 문자열 키는 pbxproj `INFOPLIST_KEY_*`, 배열 키(`UIBackgroundModes`, `CFBundleURLTypes`)는 `RunCanvas/Info.plist` 파일 (Task 0.4에서 생성).
- UI 문구 한국어. 기존 화면 스타일(흑백, 둥근 모서리 14) 유지.

---

## §0. 스펙 (와이어프레임 + 기능 목록 정리)

### MVP 1.0 기능

| # | 기능 | 와이어프레임 | 현재 코드 상태 |
|---|---|---|---|
| F1 | 회원가입/로그인 — 구글·카카오·애플 | 스플래시 → 로그인 | `LoginView`(이메일 폼 껍데기), `SignUpView`, `SplashView` → 소셜 3버튼으로 교체 |
| F2 | 마이페이지 — 닉네임·체중·프로필 이미지·로그아웃 | 러닝 설정 화면 | `ProfileView`(AppStorage 껍데기), `ProfileHeader` |
| F3 | 러닝 시작 → GPS 기록 → 일시정지 → 종료 | 홈 Run Start, 러닝 중 | `RunView`(타이머+거리만), `LocationManager`(거리만, 경로 없음) |
| F4 | 기록 저장 — 거리/시간/페이스/칼로리 계산 | 러닝 종료 | 저장 없음, 계산은 View 안에 중복 |
| F5 | 러닝 상세 — 지도 경로 + 수치 | 러닝 상세 | `RunResultView`(하드코딩) |
| F6 | 심박수 (HealthKit, 워치가 기록한 값) | 러닝 중 BPM | 없음 (capability만 추가됨) |
| F7 | 나의 기록 — 목록, 주/월/년 통계, 그래프 | 나의 기록 | `RunStatsView`(하드코딩) |
| F8 | 홈 — 최신 기록 카드, 배경 지도+현재 위치, Run Start | 홈 | `RunnerHomeView`(하드코딩, 자체 하단 탭 중복) |
| F9 | 러닝 레벨/뱃지 부여 | 프로필 | 없음 |
| F10 | 런꾸 — 배경 이미지 선택 → 기록 선택 → 스티커 편집 → 저장/공유 | 런꾸 1~4 | `RunDecorateView`(껍데기) |
| F11 | 기록 이미지 저장 및 공유 | 런꾸 4 | 없음 |

### MVP 2.0 (이 플랜 범위 밖, 스키마만 대비)

챌린지(뱃지 부여), 한국 마라톤 일정 뷰, 런꾸 월말/연말정산, Apple Watch 앱, 다른 기기로 기록 복원(서버→로컬 다운로드).

### 확정된 설계 결정

1. **기록 원본 = SwiftData 로컬.** 러닝은 통신 없는 곳에서도 끝나야 하고 저장에 실패하면 안 된다. Supabase `runs`엔 종료 후 업로드(실패 시 다음 앱 실행 때 재시도). MVP엔 다운로드 없음 → 새 폰에서 과거 기록은 안 보임(2.0).
2. **인증 = Supabase Auth.** 애플은 네이티브(`signInWithIdToken`), 구글·카카오는 `signInWithOAuth`(ASWebAuthenticationSession, 리다이렉트 `runcanvas://auth-callback`). 첫 로그인 후 `profiles` 행이 없으면 프로필 설정 화면.
3. **심박수는 읽기만.** 아이폰 단독으론 심박이 안 잡히고, 워치가 HealthKit에 쓴 샘플을 `HKAnchoredObjectQuery`로 실시간 구독한다. 종료 시 `HKWorkoutBuilder`로 러닝 워크아웃을 건강 앱에 저장. 워치 앱 자체는 2.0.
4. **레벨/뱃지 = 순수 함수.** 서버 없이 기록 배열에서 계산(`BadgeEngine`). 획득 시점만 로컬·서버에 기록.
5. **런꾸 결과물은 사진 앱 + 앱 Documents.** 서버 업로드 없음(2.0 정산에서 필요해지면 그때).
6. 하단 탭은 `RootTabView` 하나. `RunnerHomeView` 안의 자체 탭바는 제거.

### 폴더·파일 맵 (최종 형태)

```
RunCanvas/
├── App/            RunCanvasApp, RootTabView, AppRouter(로그인/온보딩/메인 분기)
├── Models/         Run (@Model), RoutePoint, Badge, Level, Profile
├── Services/       LocationService, HealthService, AuthService, ProfileService,
│                   SyncService, Supabase (클라이언트 싱글턴), RunMath, BadgeEngine
├── Features/
│   ├── Onboarding/ SplashView
│   ├── Auth/       LoginView, ProfileSetupView (SignUpView 삭제)
│   ├── Home/       RunnerHomeView, RecentRunCard
│   ├── Running/    RunView, RunSession(ViewModel), RunResultView, RunDetailView, RouteMapView
│   ├── Records/    RunStatsView, RunListView, StatsViewModel
│   ├── Canvas/     CanvasFlowView, BackgroundPickerView, RunPickerView, StickerEditorView,
│   │               StickerCanvas(렌더 대상), CanvasExportView
│   ├── Badges/     BadgeGridView, BadgeEarnedToast
│   └── Settings/   ProfileView, ProfileHeader
├── Components/     StatLabel, PrimaryButton
├── Info.plist      (배열 키 전용)
└── RunCanvasTests/ RunMathTests, RunSessionTests, BadgeEngineTests, StatsTests
```

### 페이즈 순서와 담당 제안

| Phase | 내용 | 의존 | 담당(제안) |
|---|---|---|---|
| 0 | 기반: 테스트 타깃, SPM, Supabase 프로젝트·스키마, Info.plist | — | 동하 |
| 1 | 러닝 코어: 모델·저장·경로·세션·결과·상세 | 0 | 다은 (Running 화면 작성자) |
| 2 | 로그인·프로필 (Supabase Auth/Storage) | 0 | 동하 |
| 3 | HealthKit 심박 + 워크아웃 저장 | 1 | 동하 |
| 4 | 나의 기록 통계·홈 실데이터·홈 지도 | 1 | 다은 |
| 5 | 레벨/뱃지 | 1 | 동하 |
| 6 | 런꾸 + 이미지 저장/공유 | 1 | 다은 |
| 7 | 서버 동기화 + 출시 준비 (TestFlight) | 2, 1 | 동하 |

Phase 1과 2는 병렬 가능(서로 파일이 안 겹침). 3·4·5·6은 1 머지 후 병렬 가능. 각 Phase = PR 1~3개.

---

## Phase 0 — 기반

### Task 0.1: 유닛 테스트 타깃

**Files:**
- Create (Xcode가 생성): `RunCanvasTests/RunCanvasTests.swift`
- Modify (Xcode가 수정): `RunCanvas.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `xcodebuild test` 가능한 `RunCanvasTests` 타깃. 이후 모든 태스크의 테스트가 여기 들어간다.

- [ ] **Step 1: Xcode에서 타깃 추가** — File → New → Target → iOS → **Unit Testing Bundle**, Product Name `RunCanvasTests`, Target to be Tested `RunCanvas`, Testing System **XCTest**. (pbxproj 손편집보다 Xcode가 만드는 게 안전하다.)
- [ ] **Step 2: 시뮬레이터 이름 확인**

Run: `xcrun simctl list devices available | grep -m1 iPhone`
Expected: `iPhone 17 (…)` 같은 한 줄. 아래 명령의 `name=`에 그 이름을 쓴다.

- [ ] **Step 3: 테스트 실행되는지 확인**

Run: `xcodebuild test -project RunCanvas.xcodeproj -scheme RunCanvas -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | grep -E 'Test Suite|passed|failed|error:' | tail -5`
Expected: `** TEST SUCCEEDED **` 또는 `Executed 1 test, with 0 failures`.

- [ ] **Step 4: Commit** — `git checkout -b feature/test-target develop && git add -A && git commit -m "Add RunCanvasTests unit test target"` → PR.

### Task 0.2: supabase-swift 패키지

**Files:**
- Modify (Xcode가 수정): `RunCanvas.xcodeproj/project.pbxproj`, `RunCanvas.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
- Create: `RunCanvas/Services/Supabase.swift`

**Interfaces:**
- Produces: `let supabase: SupabaseClient` 전역 상수. Phase 2·7이 사용.

- [ ] **Step 1: 패키지 추가** — Xcode → File → Add Package Dependencies → `https://github.com/supabase/supabase-swift.git`, Dependency Rule **Up to Next Major 2.0.0**, 타깃 `RunCanvas`에 product **Supabase** 추가.
- [ ] **Step 2: 클라이언트 파일**

```swift
// RunCanvas/Services/Supabase.swift
import Supabase
import Foundation

// anon(publishable) 키는 클라이언트에 넣도록 설계된 공개 키. RLS가 접근을 제한한다.
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://<PROJECT_REF>.supabase.co")!,   // Task 0.3에서 채움
    supabaseKey: "<ANON_KEY>"
)
```

- [ ] **Step 3: 빌드 확인**

Run: `xcodebuild -project RunCanvas.xcodeproj -scheme RunCanvas -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E 'error:|BUILD'`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit** — `git add -A && git commit -m "Add supabase-swift package and client"`.

### Task 0.3: Supabase 프로젝트 + 스키마 + Auth 프로바이더

**Files:**
- Create: `docs/supabase/schema.sql` (저장소에 SQL 보관)
- Modify: `RunCanvas/Services/Supabase.swift` (URL·키 채움)

**Interfaces:**
- Produces: 테이블 `profiles`, `runs`, `user_badges`, 버킷 `avatars`, RLS 정책, Auth 프로바이더 apple/google/kakao, 리다이렉트 URL `runcanvas://auth-callback`.

- [ ] **Step 1: 프로젝트 생성** — supabase.com 대시보드 → New project, 이름 `runcanvas`, region **Northeast Asia (Seoul) ap-northeast-2**, 무료 플랜. (기존 2개 프로젝트는 INACTIVE라 무관.) Project Settings → API에서 URL과 anon key를 `Supabase.swift`에 넣는다.
- [ ] **Step 2: 스키마 SQL 저장 후 SQL Editor에서 실행**

```sql
-- docs/supabase/schema.sql
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text not null,
  weight_kg double precision,
  avatar_url text,
  created_at timestamptz not null default now()
);

create table public.runs (
  id uuid primary key,                           -- 클라이언트 SwiftData Run.id 그대로
  user_id uuid not null references auth.users(id) on delete cascade,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  distance_m double precision not null,
  moving_s integer not null,
  avg_hr double precision,
  max_hr double precision,
  calories double precision not null,
  route jsonb,                                   -- [{"lat":..,"lon":..,"t":..}]
  created_at timestamptz not null default now()
);
create index runs_user_started on public.runs (user_id, started_at desc);

create table public.user_badges (
  user_id uuid not null references auth.users(id) on delete cascade,
  badge text not null,
  earned_at timestamptz not null default now(),
  primary key (user_id, badge)
);

alter table public.profiles    enable row level security;
alter table public.runs        enable row level security;
alter table public.user_badges enable row level security;

create policy "own profile" on public.profiles
  for all using (auth.uid() = id) with check (auth.uid() = id);
create policy "own runs" on public.runs
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "own badges" on public.user_badges
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

insert into storage.buckets (id, name, public) values ('avatars', 'avatars', true);
create policy "avatar read" on storage.objects
  for select using (bucket_id = 'avatars');
create policy "avatar write own folder" on storage.objects
  for insert with check (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);
create policy "avatar update own folder" on storage.objects
  for update using (bucket_id = 'avatars' and auth.uid()::text = (storage.foldername(name))[1]);
```

- [ ] **Step 3: Auth 설정** — Authentication → URL Configuration → Redirect URLs에 `runcanvas://auth-callback` 추가. Providers:
  - **Google**: Google Cloud Console에서 OAuth 클라이언트(웹 애플리케이션) 생성, Authorized redirect URI = Supabase가 보여주는 `https://<ref>.supabase.co/auth/v1/callback`. Client ID/Secret 입력.
  - **Kakao**: developers.kakao.com 앱 생성 → REST API 키 = Client ID, 보안 → Client Secret 발급·활성화, 카카오 로그인 활성화, Redirect URI에 위 callback 등록, 동의항목 이메일 필수. Supabase Kakao 프로바이더에 입력.
  - **Apple**: developer.apple.com → Identifiers → Services ID 생성(`name.dongharyu.RunCanvas.signin`), Sign in with Apple 활성화, Return URL = 위 callback. Keys에서 Sign in with Apple 키 생성(.p8). Supabase Apple 프로바이더에 Services ID·Team ID(322PTHJ258)·Key ID·.p8 입력. **네이티브 로그인은 앱 Bundle ID도 Client IDs에 추가** (`name.dongharyu.RunCanvas`). 다은 ADP 승인 후 `name.daun.RunCanvas`도 추가.
- [ ] **Step 4: 확인** — Table Editor에 테이블 3개, Storage에 `avatars` 버킷, Providers 3개 Enabled.
- [ ] **Step 5: Commit** — `git add docs/supabase/schema.sql RunCanvas/Services/Supabase.swift && git commit -m "Add Supabase schema and client config"`.

### Task 0.4: Info.plist (배열 키) + 백그라운드 위치 + URL 스킴

**Files:**
- Create: `RunCanvas/Info.plist`
- Modify: `RunCanvas.xcodeproj/project.pbxproj` (타깃 Debug/Release 2곳에 `INFOPLIST_FILE`, 동기화 그룹 예외)

**Interfaces:**
- Produces: `UIBackgroundModes = [location]`(Phase 1 백그라운드 GPS), `CFBundleURLTypes` 스킴 `runcanvas`(Phase 2 OAuth 콜백), `NSPhotoLibraryAddUsageDescription`(Phase 6 저장).

- [ ] **Step 1: Info.plist 작성**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>UIBackgroundModes</key>
	<array>
		<string>location</string>
	</array>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>runcanvas</string>
			</array>
		</dict>
	</array>
	<key>NSPhotoLibraryAddUsageDescription</key>
	<string>꾸민 러닝 이미지를 사진 앱에 저장합니다.</string>
</dict>
</plist>
```

- [ ] **Step 2: pbxproj 연결** — 타깃 레벨 Debug·Release 두 `buildSettings`(현재 `GENERATE_INFOPLIST_FILE = YES;`가 있는 곳)에 `INFOPLIST_FILE = RunCanvas/Info.plist;` 추가. `GENERATE_INFOPLIST_FILE`은 그대로 둔다(생성 키와 파일이 합쳐진다). 그리고 Info.plist가 리소스로 복사되지 않게 동기화 그룹 예외 추가:

```
/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */
		C0DE0000000000000000C003 /* Exceptions for "RunCanvas" folder in "RunCanvas" target */ = {
			isa = PBXFileSystemSynchronizedBuildFileExceptionSet;
			membershipExceptions = (
				Info.plist,
			);
			target = 15CF48802E4EF7B5002F5A44 /* RunCanvas */;
		};
/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */
```
그리고 `PBXFileSystemSynchronizedRootGroup` 항목 `15CF48832E4EF7B5002F5A44 /* RunCanvas */`에 `exceptions = ( C0DE0000000000000000C003 /* Exceptions for "RunCanvas" folder in "RunCanvas" target */, );` 한 줄 추가.

- [ ] **Step 3: 빌드 + plist 병합 확인**

Run: `xcodebuild -project RunCanvas.xcodeproj -scheme RunCanvas -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build 2>&1 | grep -E 'error:|BUILD' && plutil -p ~/Library/Developer/Xcode/DerivedData/RunCanvas-*/Build/Products/Debug-iphonesimulator/RunCanvas.app/Info.plist | grep -E 'UIBackgroundModes|runcanvas|NSHealthShare' -A1`
Expected: BUILD SUCCEEDED, 그리고 병합된 plist에 `UIBackgroundModes`, `runcanvas`, `NSHealthShareUsageDescription` 셋 다 보임.

- [ ] **Step 4: Commit** — `git add -A && git commit -m "Add Info.plist for background location and URL scheme"`.

---

## Phase 1 — 러닝 코어 (코드 레벨)

브랜치: `feature/run-core`. 이 페이즈 끝나면: 러닝 시작 → 지도에 경로 → 일시정지/재개 → 종료 → 기록이 저장되고 결과·상세 화면에 실데이터와 경로가 나온다.

### Task 1.1: Run 모델 + SwiftData 컨테이너

**Files:**
- Create: `RunCanvas/Models/Run.swift`, `RunCanvas/Models/RoutePoint.swift`
- Modify: `RunCanvas/App/RunCanvasApp.swift`

**Interfaces:**
- Produces:
  - `struct RoutePoint: Codable, Hashable { latitude: Double; longitude: Double; timestamp: Date }`
  - `@Model final class Run { id: UUID; startedAt: Date; endedAt: Date; distanceMeters: Double; movingSeconds: Int; calories: Double; averageHeartRate: Double?; maxHeartRate: Double?; route: [RoutePoint]; syncedAt: Date?; decoratedImageFilename: String? }`
  - 계산 프로퍼티 `paceSecondsPerKm: Double?`, `distanceKm: Double`
  - 앱 전체에 `.modelContainer(for: Run.self)`

- [ ] **Step 1: 모델 작성**

```swift
// RunCanvas/Models/RoutePoint.swift
import Foundation

struct RoutePoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var timestamp: Date
}
```

```swift
// RunCanvas/Models/Run.swift
import Foundation
import SwiftData

@Model
final class Run {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var endedAt: Date
    var distanceMeters: Double
    var movingSeconds: Int          // 일시정지 제외
    var calories: Double
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var route: [RoutePoint]         // ponytail: 인라인 저장. 1시간 1Hz ≈ 90KB. 장거리 기록이 많아지면 관계 테이블로 분리
    var syncedAt: Date?
    var decoratedImageFilename: String?

    init(id: UUID = UUID(), startedAt: Date, endedAt: Date, distanceMeters: Double,
         movingSeconds: Int, calories: Double, averageHeartRate: Double? = nil,
         maxHeartRate: Double? = nil, route: [RoutePoint] = []) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.distanceMeters = distanceMeters
        self.movingSeconds = movingSeconds
        self.calories = calories
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.route = route
    }

    var distanceKm: Double { distanceMeters / 1000 }
    var paceSecondsPerKm: Double? { RunMath.paceSecondsPerKm(distanceMeters: distanceMeters, seconds: movingSeconds) }
}
```

- [ ] **Step 2: 컨테이너 연결**

```swift
// RunCanvas/App/RunCanvasApp.swift
import SwiftUI
import SwiftData

@main
struct RunCanvasApp: App {
    var body: some Scene {
        WindowGroup { SplashView() }
            .modelContainer(for: Run.self)
    }
}
```

- [ ] **Step 3: 빌드** — Task 1.2가 끝나야 `RunMath`가 있어 컴파일된다. 1.2와 함께 커밋.

### Task 1.2: RunMath (페이스·칼로리·포맷) + 테스트

**Files:**
- Create: `RunCanvas/Services/RunMath.swift`
- Test: `RunCanvasTests/RunMathTests.swift`

**Interfaces:**
- Produces:
  - `RunMath.paceSecondsPerKm(distanceMeters: Double, seconds: Int) -> Double?` (거리 < 10m면 nil)
  - `RunMath.calories(distanceMeters: Double, weightKg: Double) -> Double`
  - `RunMath.formatPace(_ secondsPerKm: Double?) -> String` → `"05'30\""` / `"--'--\""`
  - `RunMath.formatDuration(_ seconds: Int) -> String` → `"02:03"`, 1시간 이상 `"1:02:03"`
  - `RunMath.formatKm(_ meters: Double) -> String` → `"5.24"`

- [ ] **Step 1: 실패하는 테스트**

```swift
// RunCanvasTests/RunMathTests.swift
import XCTest
@testable import RunCanvas

final class RunMathTests: XCTestCase {
    func testPace5kmIn30MinIs6MinPerKm() {
        XCTAssertEqual(RunMath.paceSecondsPerKm(distanceMeters: 5000, seconds: 1800), 360)
    }
    func testPaceIsNilForTinyDistance() {
        XCTAssertNil(RunMath.paceSecondsPerKm(distanceMeters: 3, seconds: 10))
    }
    func testFormatPace() {
        XCTAssertEqual(RunMath.formatPace(330), "05'30\"")
        XCTAssertEqual(RunMath.formatPace(nil), "--'--\"")
    }
    func testFormatDuration() {
        XCTAssertEqual(RunMath.formatDuration(123), "02:03")
        XCTAssertEqual(RunMath.formatDuration(3723), "1:02:03")
    }
    func testCaloriesUsesWeightTimesKm() {
        XCTAssertEqual(RunMath.calories(distanceMeters: 10_000, weightKg: 60), 621.6, accuracy: 0.01)
    }
    func testFormatKm() {
        XCTAssertEqual(RunMath.formatKm(5240), "5.24")
    }
}
```

- [ ] **Step 2: 실패 확인**

Run: `xcodebuild test -project RunCanvas.xcodeproj -scheme RunCanvas -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:RunCanvasTests/RunMathTests 2>&1 | grep -E 'error:|failed|passed' | head`
Expected: 컴파일 에러 `cannot find 'RunMath' in scope`.

- [ ] **Step 3: 구현**

```swift
// RunCanvas/Services/RunMath.swift
import Foundation

enum RunMath {
    static func paceSecondsPerKm(distanceMeters: Double, seconds: Int) -> Double? {
        guard distanceMeters >= 10 else { return nil }
        return Double(seconds) / (distanceMeters / 1000)
    }

    // 체중(kg) × 거리(km) × 1.036 — 달리기 표준 근사. 다은 코드의 식 그대로.
    static func calories(distanceMeters: Double, weightKg: Double) -> Double {
        weightKg * (distanceMeters / 1000) * 1.036
    }

    static func formatPace(_ secondsPerKm: Double?) -> String {
        guard let s = secondsPerKm, s.isFinite else { return "--'--\"" }
        let total = Int(s.rounded())
        return String(format: "%02d'%02d\"", total / 60, total % 60)
    }

    static func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    static func formatKm(_ meters: Double) -> String {
        String(format: "%.2f", meters / 1000)
    }
}
```

- [ ] **Step 4: 통과 확인** — 위 명령 재실행. Expected: `Executed 6 tests, with 0 failures`.
- [ ] **Step 5: Commit** — `git add RunCanvas/Models RunCanvas/Services/RunMath.swift RunCanvasTests/RunMathTests.swift RunCanvas/App/RunCanvasApp.swift && git commit -m "Add Run model, RunMath, and SwiftData container"`.

### Task 1.3: LocationService (경로 포인트 + 백그라운드)

**Files:**
- Create: `RunCanvas/Services/LocationService.swift`
- Delete: `RunCanvas/Features/Running/LocationManager.swift` (내용을 옮김)

**Interfaces:**
- Consumes: `RoutePoint` (1.1)
- Produces: `@Observable final class LocationService` — `authorization: CLAuthorizationStatus`, `currentLocation: CLLocation?`, `totalDistance: Double`, `route: [RoutePoint]`, `requestPermission()`, `start()`, `stop()`, `reset()`

- [ ] **Step 1: 작성** (기존 LocationManager 로직 + 경로 기록 + 백그라운드 + Observation)

```swift
// RunCanvas/Services/LocationService.swift
import Foundation
import CoreLocation
import Observation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?

    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var currentLocation: CLLocation?
    private(set) var totalDistance: Double = 0
    private(set) var route: [RoutePoint] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    func requestPermission() { manager.requestWhenInUseAuthorization() }

    func start() {
        manager.allowsBackgroundLocationUpdates = true   // Info.plist UIBackgroundModes=location 필요
        manager.showsBackgroundLocationIndicator = true
        lastLocation = nil
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
    }

    func reset() {
        totalDistance = 0
        route = []
        lastLocation = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for loc in locations {
            guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= 20 else { continue }
            currentLocation = loc
            guard let last = lastLocation else {
                lastLocation = loc
                route.append(RoutePoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, timestamp: loc.timestamp))
                continue
            }
            let d = loc.distance(from: last)
            guard d >= 5 else { continue }          // GPS 흔들림 무시
            totalDistance += d
            lastLocation = loc
            route.append(RoutePoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude, timestamp: loc.timestamp))
        }
    }
}
```

- [ ] **Step 2: LocationManager.swift 삭제** — `git rm RunCanvas/Features/Running/LocationManager.swift`. `RunView`는 Task 1.5에서 `RunSession`으로 갈아끼우므로 그때까지 빌드가 깨진다 → 1.3~1.5를 한 커밋으로 묶는다.

### Task 1.4: RunSession (러닝 상태 머신) + 테스트

**Files:**
- Create: `RunCanvas/Features/Running/RunSession.swift`
- Test: `RunCanvasTests/RunSessionTests.swift`

**Interfaces:**
- Consumes: `LocationService` (1.3), `Run`/`RunMath` (1.1, 1.2)
- Produces: `@Observable final class RunSession` — `state: State (.idle/.running/.paused/.finished)`, `elapsedSeconds: Int`, `distanceMeters`, `route`, `heartRate: Double?` (Phase 3가 채움), `start()`, `pause()`, `resume()`, `finish(weightKg: Double, context: ModelContext) -> Run`
- 시간은 타이머 틱 카운트가 아니라 **날짜 차이 누적**으로 계산(백그라운드 정지·타이머 드리프트 무관).

- [ ] **Step 1: 실패하는 테스트**

```swift
// RunCanvasTests/RunSessionTests.swift
import XCTest
import SwiftData
@testable import RunCanvas

final class RunSessionTests: XCTestCase {
    private var now = Date(timeIntervalSince1970: 1_000_000)

    private func makeSession() -> RunSession {
        RunSession(location: LocationService(), now: { self.now })
    }

    func testElapsedExcludesPausedTime() {
        let s = makeSession()
        s.start()
        now += 60
        s.pause()
        now += 30                                  // 정지 중 30초는 제외
        s.resume()
        now += 10
        XCTAssertEqual(s.elapsedSeconds, 70)
    }

    func testStateTransitions() {
        let s = makeSession()
        XCTAssertEqual(s.state, .idle)
        s.start();  XCTAssertEqual(s.state, .running)
        s.pause();  XCTAssertEqual(s.state, .paused)
        s.resume(); XCTAssertEqual(s.state, .running)
    }

    func testFinishSavesRun() throws {
        let container = try ModelContainer(for: Run.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let s = makeSession()
        s.start()
        now += 120
        let run = s.finish(weightKg: 60, context: context)
        XCTAssertEqual(s.state, .finished)
        XCTAssertEqual(run.movingSeconds, 120)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Run>()).count, 1)
    }
}
```

- [ ] **Step 2: 실패 확인** — Expected: `cannot find 'RunSession' in scope`.
- [ ] **Step 3: 구현**

```swift
// RunCanvas/Features/Running/RunSession.swift
import Foundation
import Observation
import SwiftData

@Observable
final class RunSession {
    enum State { case idle, running, paused, finished }

    private(set) var state: State = .idle
    var heartRate: Double?                // Phase 3: HealthService가 갱신
    private(set) var heartRateSamples: [Double] = []

    private let location: LocationService
    private let now: () -> Date
    private var startedAt: Date?
    private var segmentStart: Date?       // 현재 달리는 구간 시작
    private var accumulated: TimeInterval = 0
    private var ticker: Timer?
    private var tick = 0                  // 뷰 갱신용 (Observation이 변화를 감지하도록)

    init(location: LocationService = LocationService(), now: @escaping () -> Date = Date.init) {
        self.location = location
        self.now = now
    }

    var distanceMeters: Double { location.totalDistance }
    var route: [RoutePoint] { location.route }
    var currentLocation: CLLocation? { location.currentLocation }

    var elapsedSeconds: Int {
        _ = tick
        let live = segmentStart.map { now().timeIntervalSince($0) } ?? 0
        return Int((accumulated + live).rounded(.down))
    }

    func start() {
        guard state == .idle else { return }
        location.requestPermission()
        location.reset()
        location.start()
        startedAt = now()
        segmentStart = startedAt
        state = .running
        startTicker()
    }

    func pause() {
        guard state == .running, let seg = segmentStart else { return }
        accumulated += now().timeIntervalSince(seg)
        segmentStart = nil
        location.stop()
        state = .paused
        ticker?.invalidate()
    }

    func resume() {
        guard state == .paused else { return }
        segmentStart = now()
        location.start()
        state = .running
        startTicker()
    }

    @discardableResult
    func finish(weightKg: Double, context: ModelContext) -> Run {
        if state == .running { pause() }
        ticker?.invalidate()
        let run = Run(
            startedAt: startedAt ?? now(),
            endedAt: now(),
            distanceMeters: distanceMeters,
            movingSeconds: elapsedSeconds,
            calories: RunMath.calories(distanceMeters: distanceMeters, weightKg: weightKg),
            averageHeartRate: heartRateSamples.isEmpty ? nil : heartRateSamples.reduce(0, +) / Double(heartRateSamples.count),
            maxHeartRate: heartRateSamples.max(),
            route: route
        )
        context.insert(run)
        try? context.save()
        state = .finished
        return run
    }

    func recordHeartRate(_ bpm: Double) {   // Phase 3에서 호출
        heartRate = bpm
        heartRateSamples.append(bpm)
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick += 1
        }
    }
}
```
(`import CoreLocation` 추가 필요.)

- [ ] **Step 4: 통과 확인** — `-only-testing:RunCanvasTests/RunSessionTests`. Expected: 3 tests, 0 failures. (시뮬레이터에서 `LocationService`는 권한 없이도 생성만은 된다.)

### Task 1.5: RunView를 RunSession에 연결

**Files:**
- Modify: `RunCanvas/Features/Running/RunView.swift` (전면 교체)

**Interfaces:**
- Consumes: `RunSession` (1.4), `RunResultView(run:)` (1.6)
- Produces: 러닝 중 화면 — 거리·시간·페이스·칼로리·BPM(없으면 `--`), 시작/일시정지/재개, 종료 → `RunResultView(run:)` 풀스크린.

- [ ] **Step 1: 교체**

```swift
// RunCanvas/Features/Running/RunView.swift
import SwiftUI
import SwiftData

struct RunView: View {
    let startImmediately: Bool
    @Environment(\.modelContext) private var context
    @AppStorage("userWeight") private var userWeight: Double = 60
    @State private var session = RunSession()
    @State private var finishedRun: Run?

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("러닝").font(.title2).bold(); Spacer() }
                .padding(.horizontal, 24).padding(.top, 20)
            Spacer()
            VStack(spacing: 8) {
                Text("거리").font(.subheadline).foregroundStyle(.secondary)
                Text(RunMath.formatKm(session.distanceMeters)).font(.system(size: 64, weight: .bold))
                Text("km").font(.title3).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 0) {
                StatLabel(title: "시간", value: RunMath.formatDuration(session.elapsedSeconds))
                Divider().frame(height: 50)
                StatLabel(title: "페이스", value: RunMath.formatPace(RunMath.paceSecondsPerKm(distanceMeters: session.distanceMeters, seconds: session.elapsedSeconds)))
                Divider().frame(height: 50)
                StatLabel(title: "BPM", value: session.heartRate.map { "\(Int($0))" } ?? "--")
            }
            Spacer()
            PrimaryButton(
                title: session.state == .running ? "일시정지" : (session.state == .paused ? "재개" : "러닝 시작"),
                systemImage: session.state == .running ? "pause.fill" : "figure.run"
            ) {
                switch session.state {
                case .idle: session.start()
                case .running: session.pause()
                case .paused: session.resume()
                case .finished: break
                }
            }
            .padding(.horizontal, 24)
            if session.state != .idle {
                Button("러닝 종료") { finishedRun = session.finish(weightKg: userWeight, context: context) }
                    .font(.subheadline).foregroundStyle(.red).padding(.top, 16)
            }
            Spacer().frame(height: 30)
        }
        .onAppear { if startImmediately { session.start() } }
        .fullScreenCover(item: $finishedRun) { run in RunResultView(run: run) }
    }
}

#Preview { RunView(startImmediately: false).modelContainer(for: Run.self, inMemory: true) }
```
`Run`이 `.fullScreenCover(item:)`에 쓰이려면 `Identifiable` — `@Model`에 `id`가 있으므로 `extension Run: Identifiable {}`을 `Run.swift`에 추가.

- [ ] **Step 2: 공통 컴포넌트** — `RunStatView`/`ResultStatView` 중복을 하나로:

```swift
// RunCanvas/Components/StatLabel.swift
import SwiftUI

struct StatLabel: View {
    let title: String
    let value: String
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
        .frame(maxWidth: .infinity)
    }
}
```

```swift
// RunCanvas/Components/PrimaryButton.swift
import SwiftUI

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.headline).foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding()
            .background(.black).clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
```
`RunnerHomeView`, `LoginView`, `SignUpView`의 같은 모양 버튼도 `PrimaryButton`으로 교체.

### Task 1.6: RunResultView / RunDetailView / RouteMapView

**Files:**
- Modify: `RunCanvas/Features/Running/RunResultView.swift` (전면 교체)
- Create: `RunCanvas/Features/Running/RunDetailView.swift`, `RunCanvas/Features/Running/RouteMapView.swift`

**Interfaces:**
- Consumes: `Run` (1.1), `StatLabel`, `PrimaryButton` (1.5)
- Produces: `RouteMapView(route: [RoutePoint])`, `RunDetailView(run: Run)` (지도 + 수치 그리드, 홈/기록 목록에서 push), `RunResultView(run: Run)` (= 상세 + "사진으로 꾸미기"·"홈으로" 버튼, `dismiss`)

- [ ] **Step 1: 지도**

```swift
// RunCanvas/Features/Running/RouteMapView.swift
import SwiftUI
import MapKit

struct RouteMapView: View {
    let route: [RoutePoint]
    var body: some View {
        let coords = route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        Map(initialPosition: .automatic, interactionModes: []) {
            if coords.count > 1 {
                MapPolyline(coordinates: coords).stroke(.black, lineWidth: 4)
            }
            if let first = coords.first { Marker("시작", coordinate: first).tint(.green) }
            if coords.count > 1, let last = coords.last { Marker("종료", coordinate: last).tint(.red) }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
    }
}
```

- [ ] **Step 2: 상세**

```swift
// RunCanvas/Features/Running/RunDetailView.swift
import SwiftUI

struct RunDetailView: View {
    let run: Run
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                RouteMapView(route: run.route)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(spacing: 8) {
                    Text(RunMath.formatKm(run.distanceMeters)).font(.system(size: 56, weight: .bold))
                    Text("km").foregroundStyle(.secondary)
                }
                HStack(spacing: 0) {
                    StatLabel(title: "시간", value: RunMath.formatDuration(run.movingSeconds))
                    StatLabel(title: "페이스", value: RunMath.formatPace(run.paceSecondsPerKm))
                    StatLabel(title: "칼로리", value: "\(Int(run.calories.rounded()))")
                    StatLabel(title: "평균 BPM", value: run.averageHeartRate.map { "\(Int($0))" } ?? "--")
                }
                Text(run.startedAt.formatted(date: .long, time: .shortened)).font(.footnote).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .navigationTitle("러닝 상세")
    }
}
```

- [ ] **Step 3: 결과**

```swift
// RunCanvas/Features/Running/RunResultView.swift
import SwiftUI

struct RunResultView: View {
    let run: Run
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text("러닝 완료").font(.system(size: 30, weight: .bold)).padding(.top, 24)
                RunDetailView(run: run)
                PrimaryButton(title: "사진으로 꾸미기", systemImage: "photo") {
                    // Phase 6: CanvasFlowView(run: run) 연결
                }
                .padding(.horizontal, 24)
                Button("홈으로") { dismiss() }
                    .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 16)
            }
        }
    }
}
```

- [ ] **Step 4: 홈 최근 기록을 실데이터로 (최소 연결)** — `RunnerHomeView`의 하드코딩 `RunHistoryRow` 두 개를 `@Query(sort: \Run.startedAt, order: .reverse) private var runs: [Run]` + `ForEach(runs.prefix(3))` → `NavigationLink { RunDetailView(run:) }`로 교체하고, 자체 하단 탭 `HStack`(홈/러닝/나의 기록/런꾸)은 삭제(RootTabView가 담당). "오늘의 러닝 0.00"은 오늘 날짜 기록 합계로.

- [ ] **Step 5: 빌드 + 시뮬레이터 실행 확인**

Run: 빌드 명령(Task 0.2 Step 3). 이어서 시뮬레이터에서 앱 실행 → Features → Location → **City Run** → 러닝 시작 → 거리가 올라가고 → 종료 → 결과에 지도 경로가 그려지고 → 홈으로 → 최근 러닝에 방금 기록이 보이면 통과. 앱을 껐다 켜도 남아 있어야 한다.
- [ ] **Step 6: 전체 테스트** — `xcodebuild test … -only-testing:RunCanvasTests`. Expected: 9 tests, 0 failures.
- [ ] **Step 7: Commit + PR** — `git add -A && git commit -m "Record GPS runs with RunSession and show results on a map"` → `git push -u origin feature/run-core` → PR to develop.

---

## Phase 2 — 로그인·프로필 (태스크 레벨)

브랜치: `feature/auth`. 착수 시 Phase 1 형식으로 상세화.

### Task 2.1: AuthService
- Create `RunCanvas/Services/AuthService.swift`: `@Observable final class AuthService` — `session: Session?`, `userID: UUID?`, `signInWithApple(idToken: String, nonce: String) async throws`, `signInWithGoogle() async throws`, `signInWithKakao() async throws`, `signOut() async throws`, `func listen()` (`for await (event, session) in supabase.auth.authStateChanges`로 `session` 갱신).
- 구글/카카오: `try await supabase.auth.signInWithOAuth(provider: .google /* .kakao */, redirectTo: URL(string: "runcanvas://auth-callback"))` — SDK가 `ASWebAuthenticationSession`을 띄우고 콜백을 잡는다(`onOpenURL` 불필요).
- 애플: `SignInWithAppleButton`에서 `request.nonce = sha256(rawNonce)` → 완료 시 `credential.identityToken` → `supabase.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: token, nonce: rawNonce))`. 랜덤 nonce·sha256 헬퍼는 `CryptoKit`.
- **게이트**: Sign in with Apple capability(entitlement `com.apple.developer.applesignin = [Default]`)는 다은 ADP 승인 후 추가. 그 전엔 애플 버튼 없이 구글·카카오만 머지.
- 완료 조건: 시뮬레이터에서 구글 로그인 → `supabase.auth.currentSession != nil`, 대시보드 Authentication → Users에 사용자 생성.

### Task 2.2: ProfileService + Profile 모델
- Create `RunCanvas/Models/Profile.swift`: `struct Profile: Codable, Identifiable { id: UUID; nickname: String; weightKg: Double?; avatarURL: String? }` (CodingKeys snake_case).
- Create `RunCanvas/Services/ProfileService.swift`: `fetchMine() async throws -> Profile?`, `upsert(_:) async throws`, `uploadAvatar(jpeg: Data) async throws -> String` (`supabase.storage.from("avatars").upload("\(uid)/avatar.jpg", data:, options: FileOptions(contentType: "image/jpeg", upsert: true))` → `getPublicURL`).
- 완료 조건: upsert 후 Table Editor에 행 생성, avatar URL 브라우저로 열림.

### Task 2.3: 화면 연결
- `LoginView` 전면 교체: 로고 + 버튼 3개(애플·구글·카카오). 이메일 폼·`SignUpView` 삭제.
- Create `Features/Auth/ProfileSetupView.swift`: 닉네임·체중(첫 로그인, `profiles` 행 없을 때만).
- Create `App/AppRouter.swift`: `SplashView` 2초 후 → 세션 없음 → `LoginView` / 세션 있음+프로필 없음 → `ProfileSetupView` / 둘 다 → `RootTabView`. `RunCanvasApp`의 루트를 `AppRouter()`로.
- `ProfileView`: 닉네임·체중은 `ProfileService`로 저장(체중은 `@AppStorage("userWeight")`에도 복사 — RunSession이 오프라인에서 쓴다), `PhotosPicker`로 프로필 이미지 → `uploadAvatar`, 로그아웃 버튼 → `signOut()` → AppRouter가 LoginView로. `ProfileHeader`는 `AsyncImage(url:)`로 아바타 표시.
- 완료 조건: 로그아웃 → 앱 재시작 → 로그인 화면, 로그인 → 홈. 프로필 이미지가 홈 헤더에 뜸.

---

## Phase 3 — HealthKit 심박 (태스크 레벨)

브랜치: `feature/heart-rate`. 의존: Phase 1.

### Task 3.1: HealthService
- Create `RunCanvas/Services/HealthService.swift`: `requestAuthorization() async throws` (read `HKQuantityType(.heartRate)`, share `HKObjectType.workoutType()`, `HKQuantityType(.distanceWalkingRunning)`, `HKQuantityType(.activeEnergyBurned)`), `startHeartRateStream(since: Date, onSample: @escaping (Double) -> Void)` (`HKAnchoredObjectQuery` + `updateHandler`, 단위 `HKUnit.count().unitDivided(by: .minute())`), `stopHeartRateStream()`, `saveWorkout(_ run: Run) async throws` (`HKWorkoutBuilder(healthStore:configuration:device:)`, `activityType = .running`, `beginCollection` → 거리·칼로리 샘플 `add` → `endCollection` → `finishWorkout`).
- 완료 조건: 실기기 + 애플워치에서 워치 워크아웃을 켜고 앱 러닝 시작 → BPM이 갱신. 종료 후 건강 앱에 러닝 워크아웃이 보임. (시뮬레이터: 건강 앱에 수동 심박 샘플 추가로 스트림 확인.)

### Task 3.2: RunSession 연결
- `RunSession.start()`에서 `health.startHeartRateStream(since: startedAt) { [weak self] in self?.recordHeartRate($0) }`, `finish()`에서 `stop` + `Task { try? await health.saveWorkout(run) }`.
- `RunSessionTests`에 `HealthService`를 주입하지 않도록 `init(location:health:now:)`에서 `health: HealthService? = nil` 기본값 — 테스트는 nil.
- 권한 요청은 `RunView.onAppear`에서 위치 권한과 함께.

---

## Phase 4 — 나의 기록·홈 (태스크 레벨)

브랜치: `feature/records`. 의존: Phase 1.

### Task 4.1: StatsViewModel + 테스트
- Create `RunCanvas/Features/Records/StatsViewModel.swift`: `enum Period { week, month, year }`, `struct Bucket { label: String; distanceMeters: Double }`, `static func summary(runs: [Run], period: Period, now: Date) -> (totalMeters: Double, count: Int, avgPace: Double?, totalSeconds: Int)`, `static func buckets(runs:, period:, now:) -> [Bucket]` (주=요일 7개, 월=일별, 년=월 12개). `Calendar.current` 주입 가능.
- Test `RunCanvasTests/StatsTests.swift`: 이번 주 3건 합계, 지난 주 기록 제외, 빈 배열 → 0.

### Task 4.2: RunStatsView 실데이터
- `RunStatsView`: `@Query` 전체 기록, `Picker` 주/월/년, 상단 큰 숫자(총 km), `StatLabel` 3개(횟수·평균 페이스·시간), `Chart { BarMark(x: .value("기간", bucket.label), y: .value("km", bucket.distanceMeters / 1000)) }`.
- 하단 `RunListView`: 날짜 역순 목록 → `RunDetailView`. 스와이프 삭제(`context.delete(run)`).

### Task 4.3: 홈 마무리
- `RunnerHomeView`: 배경에 `Map(position: .constant(.userLocation(fallback: .automatic)))` + `UserAnnotation()` (`LocationService.requestPermission()` onAppear), 위에 최신 기록 카드(`RecentRunCard`: 거리·시간·페이스·날짜, 탭 → 상세), 플로팅 "Run Start" 원형 버튼 → `RunView(startImmediately: true)`. 와이어프레임의 "화면 스와이프로 뷰 이동"은 탭바로 대체(결정 6).

---

## Phase 5 — 레벨/뱃지 (태스크 레벨)

브랜치: `feature/badges`. 의존: Phase 1.

### Task 5.1: Badge/Level 모델 + BadgeEngine + 테스트
- Create `RunCanvas/Models/Badge.swift`: `enum Badge: String, CaseIterable, Codable { firstRun, fiveK, tenK, halfMarathon, streak7, total100km }` + `title`, `symbolName`, `description`.
- Create `RunCanvas/Models/Level.swift`: `struct Level { number: Int; title: String; nextThresholdMeters: Double? }`, `static func forTotalDistance(_ meters: Double) -> Level` — 구간 `[0, 10km, 50km, 100km, 250km, 500km, 1000km]` → Lv1~7 (`입문·초보·러너·꾸준·중급·상급·마스터`).
- Create `RunCanvas/Services/BadgeEngine.swift`: `static func earned(runs: [Run], calendar: Calendar = .current) -> Set<Badge>` — 순수 함수. `streak7`은 연속 7일 각각 기록 존재.
- Test `RunCanvasTests/BadgeEngineTests.swift`: 5km 1회 → `{firstRun, fiveK}`, 7일 연속 → `streak7` 포함, 6일 연속 → 미포함, 총 100km → `total100km`. `Level.forTotalDistance(10_000).number == 2`.

### Task 5.2: 표시 + 획득 알림
- `@AppStorage("earnedBadges") var earnedBadgesRaw: String` (콤마 구분)에 획득 목록 캐시. `RunResultView` 등장 시 `BadgeEngine.earned(runs:)`와 비교 → 새 뱃지면 `BadgeEarnedToast` 오버레이 + Supabase `user_badges` upsert(Phase 7 SyncService 경유, 실패 무시).
- `ProfileView` 상단에 `Level` 카드(현재 레벨, 다음 레벨까지 km 프로그레스) + `BadgeGridView`(획득=컬러, 미획득=회색).

---

## Phase 6 — 런꾸 (태스크 레벨)

브랜치: `feature/canvas`. 의존: Phase 1. 와이어프레임 런꾸 1~4 순서 그대로 4화면.

### Task 6.1: 플로우 + 배경 선택 (런꾸 1)
- Create `Features/Canvas/CanvasFlowView.swift`: `NavigationStack` + `@State var background: CanvasBackground` (`enum CanvasBackground { case preset(Int), photo(UIImage) }`), `@State var run: Run?`. `RunResultView`의 "사진으로 꾸미기"가 `run`을 넣어 연다(런꾸 2 건너뜀). 탭에서 열면 `run == nil`.
- Create `BackgroundPickerView.swift`: 기본 이미지 6종(그라데이션/단색, Assets에 추가) 그리드 + `PhotosPicker`(앨범) + 카메라(`UIImagePickerController` 래퍼 `CameraPicker`).
- `RunDecorateView` 삭제, `RootTabView` 런꾸 탭 → `CanvasFlowView()`.

### Task 6.2: 기록 선택 (런꾸 2)
- Create `RunPickerView.swift`: `@Query` 목록(날짜·거리·시간) → 선택 → `run` 세팅.

### Task 6.3: 스티커 편집 (런꾸 3)
- Create `Models/Sticker.swift`: `struct Sticker: Identifiable { id; kind: Kind (.distance/.time/.pace/.date/.calories/.heartRate/.route/.text(String)); position: CGPoint; scale: CGFloat; opacity: Double; fontStyle: FontStyle }`.
- Create `StickerCanvas.swift`: 배경 이미지 위에 `ForEach(stickers)` — 각 스티커 `DragGesture` + `MagnifyGesture`, `route` 스티커는 `Path`로 경로 실루엣. **이 뷰가 렌더 대상**(편집 UI와 분리).
- Create `StickerEditorView.swift`: `StickerCanvas` + 하단 툴바(스티커 추가 메뉴, 선택 스티커 불투명도 슬라이더, 글자 스타일 3종, 텍스트 입력).

### Task 6.4: 저장·공유 (런꾸 4)
- Create `CanvasExportView.swift`: 미리보기 + 버튼 — **사진 앱 저장**(`ImageRenderer(content: StickerCanvas(...))`, `scale = 3`, `UIImageWriteToSavedPhotosAlbum`), **공유**(`ShareLink(item: Image(uiImage:), preview:)`), **다시 수정**(pop), **앱 앨범 저장**(JPEG를 `Documents/canvas/<run.id>.jpg`에 쓰고 `run.decoratedImageFilename` 세팅 → 상세 화면·2.0 정산에서 사용).
- 완료 조건: 사진 앱에 3배 해상도 이미지, 공유 시트 동작, 앱 재시작 후 상세에서 꾸민 이미지 표시.

---

## Phase 7 — 동기화 + 출시 준비 (태스크 레벨)

브랜치: `feature/sync`. 의존: Phase 1, 2.

### Task 7.1: SyncService
- Create `Models/RunDTO.swift`: `runs` 테이블 컬럼과 1:1 `Codable` (route → `[["lat":..,"lon":..,"t":..]]`), `init(run: Run, userID: UUID)`.
- Create `Services/SyncService.swift`: `pushPending(context: ModelContext) async` — `FetchDescriptor<Run>(predicate: #Predicate { $0.syncedAt == nil })` → `supabase.from("runs").upsert(dtos).execute()` → 성공한 것만 `syncedAt = now`. 뱃지도 `user_badges` upsert.
- 호출 시점: `RunResultView` 등장 시, 앱 `scenePhase == .active` 될 때. 오프라인이면 조용히 실패.
- 완료 조건: 비행기 모드로 러닝 종료 → 네트워크 켜고 홈 복귀 → 대시보드 `runs`에 행 생성, 두 번 실행해도 중복 없음(upsert).

### Task 7.2: 출시 준비
- 앱 아이콘(1024 + 다크/틴트), 런치 스크린 색, `MARKETING_VERSION = 1.0`.
- 권한 문구 검토: 위치·건강(읽기/쓰기)·사진 추가. 배경 위치 인디케이터 문구.
- Sign in with Apple capability 추가(다은 ADP 승인 후 — Global Constraints).
- 동하 맥에서 Archive → TestFlight 내부 테스트(다은 = 내부 테스터, ASC 초대 수락 상태).
- App Store 심사 대비: 소셜 로그인이 있으므로 Apple 로그인 필수, 계정 삭제 기능 필수(가이드라인 5.1.1(v)) → `ProfileView`에 "계정 삭제"(Supabase Edge Function 없이: `supabase.auth.admin`은 클라이언트 불가 → **RPC 함수 `delete_own_account()`를 schema.sql에 추가**: `security definer`로 `auth.users`에서 `auth.uid()` 삭제).

---

## MVP 2.0 백로그 (착수 시 별도 플랜)

- 챌린지: `challenges`, `challenge_participants` 테이블, 기간·목표 km, 완료 시 뱃지 부여(서버 함수).
- 한국 마라톤 일정: 정적 JSON(`Resources/marathons.json`, 월 1회 갱신) → 목록/캘린더 뷰. 외부 API 없음.
- 런꾸 월말/연말정산: `runs` 집계 + 해당 기간 `decoratedImageFilename` 콜라주 → `ImageRenderer`.
- Apple Watch 앱: `HKWorkoutSession`으로 워치 단독 러닝, App Groups(`group.$(PRODUCT_BUNDLE_IDENTIFIER)`)로 공유.
- 서버 → 로컬 기록 복원(새 기기 로그인 시 `runs` 다운로드).

---

## Self-Review

- **스펙 커버리지**: F1→2.1/2.3, F2→2.2/2.3, F3→1.3/1.4/1.5, F4→1.2/1.4, F5→1.6, F6→3.x, F7→4.1/4.2, F8→1.6 Step 4 + 4.3, F9→5.x, F10→6.1~6.3, F11→6.4. 2.0 항목은 백로그.
- **플레이스홀더**: Phase 1은 코드 완결. Phase 2~7은 의도적으로 태스크 레벨(파일·시그니처·완료 조건)이며 착수 시 Phase 1 형식으로 상세화한다 — "TBD"는 없음.
- **타입 일관성**: `RoutePoint(latitude:longitude:timestamp:)`, `Run.movingSeconds`, `RunMath.paceSecondsPerKm(distanceMeters:seconds:)`, `RunSession.finish(weightKg:context:)`, `StatLabel(title:value:)`, `PrimaryButton(title:systemImage:action:)`, `RunDetailView(run:)`, `RunResultView(run:)`, `RouteMapView(route:)` — 전 페이즈 동일 명칭 사용 확인.
