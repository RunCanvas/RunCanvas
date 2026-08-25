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
├── App/          앱 진입점, RootTabView (탭: 홈·기록·런구·설정)
├── Models/       Run(거리·페이스·시간·BPM·경로·날짜), RunSettings
├── Services/     LocationService(GPS), HealthService(심박·워치), RunStore(저장)
├── Features/     화면 묶음별 폴더 — View + ViewModel을 같은 폴더에
│   ├── Home/       지도 + 최신 기록 카드 + Run Start
│   ├── Running/    러닝 중, 일시정지
│   ├── Records/    주·월·년 그래프 + 목록
│   ├── Canvas/     런구 1~4 (배경 선택 → 기록 선택 → 편집 → 저장·공유)
│   └── Settings/   러닝 설정, Apple Watch
├── Components/   공통 UI (StatLabel, MapView 래퍼, DesignSystem)
└── Assets.xcassets
```

Xcode 동기화 폴더라 Finder에서 폴더·파일을 만들면 프로젝트에 자동 반영됩니다.

## 다른 Apple 계정으로 실기기 빌드 (팀원용)

서명 Team·Bundle ID는 `Config/Base.xcconfig`에 있고, 같은 폴더의 `Local.xcconfig`(gitignore)가 있으면 그 값으로 덮어씁니다. **Xcode의 Signing & Capabilities에서 Team을 직접 바꾸지 마세요** — pbxproj에 기록돼 충돌납니다.

1. Xcode → Settings → Accounts → `+` → 본인 Apple ID 추가 (무료 계정이면 "Personal Team" 생성됨)
2. 팀 ID 확인: Signing & Capabilities에서 Team을 잠깐 본인 팀으로 바꾼 뒤 터미널에서 `git diff`로 `DEVELOPMENT_TEAM = XXXXXXXXXX` 값을 복사하고, `git checkout -- RunCanvas.xcodeproj/project.pbxproj`로 되돌립니다
3. `Config/Local.xcconfig` 생성:
   ```
   DEVELOPMENT_TEAM = XXXXXXXXXX
   PRODUCT_BUNDLE_IDENTIFIER = name.<본인이름>.RunCanvas
   ```
4. 아이폰 개발자 모드 켜고 연결 → ⌘R → 설정 → 일반 → VPN 및 기기 관리 → 개발자 앱 신뢰

무료 Personal Team은 앱이 7일마다 만료되므로 다시 ⌘R 하면 됩니다. HealthKit은 되지만 App Groups·iCloud·푸시는 유료 계정이 필요합니다.
